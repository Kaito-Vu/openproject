module OpenProject::UxEnhancements
  class Hooks < ::OpenProject::Hook::ViewListener
    render_on :view_layouts_base_html_head, partial: "ux_enhancements/head"
    render_on :view_layouts_base_body_bottom, partial: "ux_enhancements/body_bottom"
  end
end
