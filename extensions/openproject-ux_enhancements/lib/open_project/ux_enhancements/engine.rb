require "open_project/plugins"

module OpenProject::UxEnhancements
  class Engine < ::Rails::Engine
    engine_name :openproject_ux_enhancements

    include OpenProject::Plugins::ActsAsOpEngine

    register "openproject-ux_enhancements", author_url: "https://etc.vn"

    # Plugin locale files (config/locales/crowdin/*.yml) load after core's, so they override core keys.
    config.to_prepare { require "open_project/ux_enhancements/hooks" }
  end
end
