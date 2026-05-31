require "uri"

# Return true if the provided icon is in a valid URL format.
def valid_url?(icon)
  return false if icon.nil? || (!icon.start_with?("http://") && !icon.start_with?("https://"))

  uri = URI.parse(icon)
  return uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
rescue URI::InvalidURIError => e
  halt 500, e.message
end

# Resolves the appropriate icon path based on the provided icon and directory name.
def get_icon_path(dirname, icon)
  is_bi_or_fa_icon = false # Bootstrap icon or Font Awesome icon
  icon_path = if icon.nil?
                URI.join(url, "no_image_square.jpg")
              elsif valid_url?(icon)
                icon
              else
                tmp_icon_path = File.join("/", @apps_dir, dirname, icon)
                icon_local_path = File.join(Dir.pwd, tmp_icon_path)

                if File.exist?(icon_local_path)
                  File.join(@script_name, tmp_icon_path)
                elsif icon.start_with?("bi-", "fa-")
                  is_bi_or_fa_icon = true
                  nil
                else
                  URI.join(url, "no_image_square.jpg")
                end
              end

  [is_bi_or_fa_icon, icon_path]
end

helpers do
  # Create an HTML snippet for a user template card with a delete button.
  def output_template_thumbnail(slug, name, description, app_path, icon)
    width      = @conf['thumbnail_width']
    safe_nm    = ERB::Util.h(name)
    safe_dsc   = ERB::Util.h(description.to_s)
    enc_slug   = ERB::Util.u(slug)
    safe_cfm   = name.gsub("\\", "\\\\\\\\").gsub("'", "\\'")
    safe_app   = ERB::Util.h(app_path.to_s)
    desc_html  = description.to_s.strip.empty? ? "" :
      "<div class=\"small text-muted mt-1\" style=\"word-break:break-word;\">#{safe_dsc}</div>"

    raw_icon  = icon.to_s
    icon_html = if raw_icon.start_with?("bi-", "fa-")
      "<i class=\"#{ERB::Util.h(raw_icon)}\" style=\"font-size: #{width}px; width: #{width}px; height: 100px; line-height: 1;\"></i>"
    elsif raw_icon.start_with?("http://", "https://")
      "<img src=\"#{ERB::Util.h(raw_icon)}\" class=\"img-thumbnail\" width=\"#{width}\" height=\"100\" alt=\"#{safe_nm}\">"
    elsif !raw_icon.empty?
      url_path = if app_path.to_s.start_with?("_generic/")
        gd  = @conf["generic_apps_dir"] || "./generic_apps"
        sub = app_path.sub(/\A_generic\//, "")
        local = File.join(Dir.pwd, gd, sub, raw_icon)
        File.exist?(local) ? File.join(@script_name, "/", gd, sub, raw_icon) : nil
      else
        tp    = File.join("/", @apps_dir, app_path, raw_icon)
        local = File.join(Dir.pwd, tp)
        File.exist?(local) ? File.join(@script_name, tp) : nil
      end
      url_path ? "<img src=\"#{ERB::Util.h(url_path)}\" class=\"img-thumbnail\" width=\"#{width}\" height=\"100\" alt=\"#{safe_nm}\">" :
                 "<i class=\"bi bi-file-earmark-code\" style=\"font-size: #{width}px; width: #{width}px; height: 100px; line-height: 1;\"></i>"
    else
      "<i class=\"bi bi-file-earmark-code\" style=\"font-size: #{width}px; width: #{width}px; height: 100px; line-height: 1;\"></i>"
    end

    <<~HTML
      <div class="col text-center">
        <div class="d-flex flex-column h-100 align-items-center position-relative">
          <div class="position-absolute top-0 end-0 d-flex gap-1" style="z-index:5;">
            <button type="button" class="btn btn-sm btn-link text-secondary p-0 lh-1"
                    title="Edit template"
                    data-bs-toggle="modal" data-bs-target="#modal-rename-template"
                    data-slug="#{enc_slug}" data-name="#{safe_nm}" data-desc="#{safe_dsc}">
              <i class="bi bi-pencil-fill fs-6"></i>
            </button>
            <form method="post" action="#{@script_name}/templates/#{enc_slug}/delete">
              <button type="submit" class="btn btn-sm btn-link text-danger p-0 lh-1"
                      title="Delete template"
                      onclick="return confirm('Delete template \\'#{safe_cfm}\\'?')">
                <i class="bi bi-x-circle-fill fs-6"></i>
              </button>
            </form>
          </div>
          <div class="flex-grow-1 d-flex align-items-center">
            <a href="#{@script_name}/#{safe_app}?template=#{enc_slug}" class="stretched-link position-relative text-reset">
              #{icon_html}
            </a>
          </div>
          #{safe_nm}
          #{desc_html}
        </div>
      </div>
    HTML
  end

  # Create an HTML snippet for displaying a thumbnail image.
  # The image source can either be a URL, a bootstrap icon, a fontawesome icon or a local path.
  # If the icon is not provided. a placeholder image is used.
  def output_thumbnail(dirname, name, icon)
    is_bi_or_fa_icon, icon_path = get_icon_path(dirname, icon)

    # Use the text-reset class to prevent color changes when using font awesome icons
    html = <<~HTML
      <div class="col text-center">
        <div class="d-flex flex-column h-100 align-items-center">
          <div class="flex-grow-1 d-flex align-items-center">
            <a href="#{@script_name}/#{dirname}" class="stretched-link position-relative text-reset">
HTML
    width = @conf['thumbnail_width']
    if is_bi_or_fa_icon
      html << "<i class=\"#{icon}\" style=\"font-size: #{width}px; width: #{width}px; height: 100px; line-height: 1;\"></i>"
    else
      html << "<img src=\"#{icon_path}\" class=\"img-thumbnail\" width=\"#{width}\" height=\"100\" alt=\"#{name}\">"
    end
    html << <<~HTML
             </a>
           </div>
        #{name}
        </div>
      </div>
    HTML
  end
end
