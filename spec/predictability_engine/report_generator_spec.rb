# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe PredictabilityEngine::ReportGenerator do
  let(:tmpdir) { Dir.mktmpdir('report-generator-spec') }

  after do
    FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir)
  end

  let(:input_file) { File.join(tmpdir, 'sample.csv') }
  let(:all_report) do
    instance_double(PredictabilityEngine::Report, render: 'all content', generate_chart_images: 'images')
  end
  let(:bug_report) do
    instance_double(PredictabilityEngine::Report, render: 'bug content', generate_chart_images: 'images')
  end
  let(:high_report) do
    instance_double(PredictabilityEngine::Report, render: 'high content', generate_chart_images: 'images')
  end

  describe '.run_report' do
    let(:items) { [Object.new] }

    before do
      allow(PredictabilityEngine).to receive(:load_items).with(input_file, color: true).and_return(items)
      allow(PredictabilityEngine::Report).to receive(:generate_all).with(items).and_return(all: all_report)
    end

    it 'loads items, builds reports, and generates a single report when there are no facets' do
      allow(described_class).to receive(:generate_single_report).and_return('single report')

      result = described_class.run_report(input_file, :html, color: true)

      expect(result).to eq('single report')
      expect(described_class).to have_received(:generate_single_report).with(input_file, :html, all_report, color: true)
    end

    it 'uses provided items and reports without loading or rebuilding them' do
      reports = { all: all_report }
      allow(described_class).to receive(:generate_single_report).and_return('provided report')

      result = described_class.run_report(input_file, :html, items: items, reports: reports)

      expect(result).to eq('provided report')
      expect(PredictabilityEngine).not_to have_received(:load_items)
      expect(PredictabilityEngine::Report).not_to have_received(:generate_all)
    end

    it 'generates terminal output as a single report even when facet reports exist' do
      reports = { all: all_report, type: { 'Bug' => bug_report } }
      allow(described_class).to receive(:generate_single_report).and_return('terminal report')

      result = described_class.run_report(input_file, :terminal, items: items, reports: reports)

      expect(result).to eq('terminal report')
      expect(described_class).to have_received(:generate_single_report).with(input_file, :terminal, all_report)
    end

    it 'generates multiple reports when facet reports exist for non-terminal formats' do
      reports = { all: all_report, type: { 'Bug' => bug_report } }
      allow(described_class).to receive(:generate_multi_reports).and_return('2 reports generated')

      result = described_class.run_report(input_file, :html, items: items, reports: reports)

      expect(result).to eq('2 reports generated')
      expect(described_class).to have_received(:generate_multi_reports).with(input_file, :html, reports)
    end
  end

  describe '.facet_total' do
    it 'counts all configured facet entries' do
      reports = { all: all_report, priority: { 'High' => high_report }, type: { 'Bug' => bug_report } }

      expect(described_class.facet_total(reports)).to eq(2)
    end
  end

  describe '.each_facet_entry' do
    it 'yields the all report first and then each facet report' do
      reports = { all: all_report, priority: { 'High' => high_report }, type: { 'Bug' => bug_report } }
      entries = []

      described_class.each_facet_entry(reports) { |slot, report| entries << [slot, report] }

      expect(entries).to eq([
                              [:all, all_report],
                              [[:priority, 'High'], high_report],
                              [[:type, 'Bug'], bug_report]
                            ])
    end
  end

  describe '.generate_single_report' do
    it 'returns terminal content without writing a file' do
      expect(described_class).not_to receive(:write_report)

      result = described_class.generate_single_report(input_file, :terminal, all_report, color: true)

      expect(result).to eq('all content')
      expect(all_report).to have_received(:render).with(:terminal, color: true)
    end

    it 'adds export links when rendering an HTML dashboard without explicit sub-reports' do
      allow(described_class).to receive(:write_report).and_return('written')

      described_class.generate_single_report(input_file, :html, all_report, output_dir: tmpdir)

      expect(all_report).to have_received(:render).with(:html, output_dir: tmpdir,
                                                               sub_reports: described_class.export_links_for(:all))
    end

    it 'generates inline chart images before rendering markdown' do
      allow(described_class).to receive(:write_report).and_return('written')

      described_class.generate_single_report(input_file, :markdown, all_report, output_dir: tmpdir)

      expect(all_report).to have_received(:generate_chart_images)
        .with(File.join(tmpdir, 'sample'))
      expect(all_report).to have_received(:render).with(:markdown, output_dir: tmpdir)
    end
  end

  describe '.generate_multi_reports' do
    it 'writes one dashboard and one file per facet value with matching navigation links' do
      logger = instance_double(SemanticLogger::Logger, info: nil)
      reports = { all: all_report, type: { 'Bug' => bug_report } }
      allow(PredictabilityEngine).to receive(:logger).and_return(logger)

      result = described_class.generate_multi_reports(input_file, :html, reports, output_dir: tmpdir)

      expect(result).to eq('2 reports generated')
      expect(File.binread(File.join(tmpdir, 'sample', 'dashboard.html'))).to eq('all content')
      expect(File.binread(File.join(tmpdir, 'sample', 'types', 'Bug.html'))).to eq('bug content')
      expect(all_report).to have_received(:render).with(:html, output_dir: tmpdir,
                                                               sub_reports: described_class.build_nav_links(:html,
                                                                                                             reports,
                                                                                                             :all))
      bug_links = described_class.build_nav_links(:html, reports, [:type, 'Bug'])
      expect(bug_report).to have_received(:render).with(:html, output_dir: tmpdir, sub_reports: bug_links)
      expect(logger).to have_received(:info).twice
    end
  end

  describe '.build_nav_links' do
    it 'returns nil for non-HTML formats' do
      expect(described_class.build_nav_links(:markdown, { all: all_report }, :all)).to be_nil
    end

    it 'builds relative links from a facet dashboard back to the main dashboard and sibling facets' do
      reports = { all: all_report, priority: { 'High' => high_report }, type: { 'Bug' => bug_report } }

      links = described_class.build_nav_links(:html, reports, [:type, 'Bug'])

      expect(links).to include(label: 'All', url: '../dashboard.html', active: false)
      expect(links).to include(label: 'High', url: '../priorities/High.html', active: false)
      expect(links).to include(label: 'Bug', url: 'Bug.html', active: true)
      expect(links).to include(label: 'CSV', url: '../dashboard.csv', download: true)
    end
  end

  describe '.write_report' do
    it 'writes the main report to the dashboard filename for aliased formats' do
      message = described_class.write_report(input_file, :landscape, 'html', nil, output_dir: tmpdir)
      output = File.join(tmpdir, 'sample', 'dashboard.html')

      expect(File.binread(output)).to eq('html')
      expect(message).to eq("Report generated at #{output}")
    end

    it 'writes facet reports below the facet directory' do
      described_class.write_report(input_file, :markdown, 'body', nil, slot: [:priority, 'High'], output_dir: tmpdir)

      expect(File.binread(File.join(tmpdir, 'sample', 'priorities', 'High.md'))).to eq('body')
    end

    it 'honors an explicit output path for the all report' do
      output = File.join(tmpdir, 'custom.conf')

      message = described_class.write_report(input_file, :confluence, 'content', output, output_dir: tmpdir)

      expect(File.binread(output)).to eq('content')
      expect(message).to eq("Report generated at #{output}")
    end
  end

  describe '.report_dir' do
    it 'uses reports next to the input file by default' do
      expect(described_class.report_dir(input_file)).to eq(File.join(tmpdir, 'reports', 'sample'))
    end

    it 'uses the configured output directory when present' do
      expect(described_class.report_dir(input_file, output_dir: 'out')).to eq(File.join('out', 'sample'))
    end
  end

  describe '.clean_report_dir' do
    it 'removes the generated report directory' do
      dir = File.join(tmpdir, 'sample')
      FileUtils.mkdir_p(dir)

      described_class.clean_report_dir(input_file, output_dir: tmpdir)

      expect(File).not_to exist(dir)
    end
  end

  describe '.dashboard_filename' do
    it 'uses stable dashboard names for special formats' do
      expect(described_class.dashboard_filename(:a3_landscape, 'pdf')).to eq('dashboard_a3.pdf')
      expect(described_class.dashboard_filename(:png, 'png')).to eq('dashboard.png')
      expect(described_class.dashboard_filename(:raw_csv, 'csv')).to eq('dashboard.csv')
    end
  end
end
