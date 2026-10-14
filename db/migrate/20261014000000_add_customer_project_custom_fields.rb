class AddCustomerProjectCustomFields < ActiveRecord::Migration[8.1]
  FIELDS = [
    { name: "Loại khách hàng", field_format: "list", possible_values: %w[Internal External] },
    { name: "Tên khách hàng", field_format: "string" },
    { name: "Số hợp đồng", field_format: "string" },
    { name: "Thời gian bắt đầu", field_format: "date" },
    { name: "Thời gian dự kiến kết thúc", field_format: "date" }
  ].freeze

  def up
    section = ProjectCustomFieldSection.first || ProjectCustomFieldSection.create!(name: "Thông tin khách hàng")

    FIELDS.each do |attrs|
      next if ProjectCustomField.exists?(name: attrs[:name])

      # is_for_all => enabled (and shown in the create form) for every project
      ProjectCustomField.create!(attrs.merge(is_for_all: true, project_custom_field_section: section))
    end
  end

  def down
    ProjectCustomField.where(name: FIELDS.pluck(:name)).destroy_all
  end
end
