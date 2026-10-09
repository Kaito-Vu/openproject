# frozen_string_literal: true

require "mini_magick"

module OpenIDConnect
  # Pulls the user's profile photo from Microsoft Graph using the OIDC access token
  # (needs the User.Read delegated permission) and stores it as the local avatar.
  class EntraAvatarSyncService
    PHOTO_URL = "https://graph.microsoft.com/v1.0/me/photos/96x96/$value"

    def initialize(user)
      @user = user
    end

    def call(access_token:)
      return unless @user.respond_to?(:local_avatar_attachment=)

      response = OpenProject.httpx.get(PHOTO_URL, headers: { "Authorization" => "Bearer #{access_token}" })
      return unless response.status == 200 # 404 = user has no photo, 401/403 = missing scope

      store(response.body.to_s)
    rescue StandardError => e
      # Avatar sync must never block a login
      Rails.logger.warn { "Entra avatar sync failed for user##{@user.id}: #{e.message}" }
    end

    private

    def store(data)
      Tempfile.create(["entra-avatar", ".jpg"], binmode: true) do |file|
        file.write(data)
        file.flush

        # Graph can return a larger image than requested; Avatars::UpdateService caps at 128px
        MiniMagick::Image.new(file.path).resize("128x128>").write(file.path)

        @user.local_avatar_attachment = OpenProject::Files.build_uploaded_file(file, "image/jpeg", file_name: "avatar.jpg")
      end
    end
  end
end
