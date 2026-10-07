# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenProject::IssueView do
  let(:module_root) { Pathname.new(__dir__).join("../../../..").expand_path }
  let(:sources) { Dir[module_root.join("{app,lib}/**/*.rb").to_s] }

  it "passes the core dependency guard" do
    expect { described_class.assert_core_dependencies! }.not_to raise_error
  end

  it "fails with the missing dependency name" do
    stub_const("OpenProject::IssueView::CORE_DEPENDENCIES", { "Fake#thing" => -> { false } })
    expect { described_class.assert_core_dependencies! }.to raise_error(/Fake#thing/)
  end

  it "mounts the endpoint under work packages" do
    paths = API::V3::Root.routes.map(&:path)
    expect(paths).to include(a_string_matching(%r{/work_packages/:id/issue_view}))
  end

  it "has no jira naming, shared cache, ETag or ad-hoc authorization" do
    code = sources.map { |file| File.read(file) }.join("\n")

    expect(sources.join).not_to match(/jira/i)
    expect(code).not_to match(/jira/i)
    expect(code).not_to include("authorize_logged_in")
    expect(code).not_to match(/Rails\.cache|ETag|etag_for/)
  end
end
