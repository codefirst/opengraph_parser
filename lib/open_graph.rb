require 'nokogiri'
require 'redirect_follower'
require "addressable/uri"
require 'uri'

class OpenGraph
  attr_accessor :src, :url, :type, :title, :description, :images, :metadata, :response, :original_images

  def initialize(src, fallback = true, options = {})
    if fallback.is_a? Hash
      options = fallback
      fallback = true
    end
    @src = src
    @body = nil
    @charset = 'utf-8'
    @images = []
    @metadata = {}
    parse_opengraph(options)
    load_fallback if fallback
    check_images_path
  end

  private
  def parse_opengraph(options = {})
    begin
      if @src.include? '</html>'
        @body = @src
      else
        resolved = RedirectFollower.new(@src, options).resolve
        @body = resolved.body
        @charset = resolved.charset
      end
    rescue
      @title = @url = @src
      return
    end

    if @body
      attrs_list = %w(title url type description)
      doc = parse_html(@body, @charset)
      doc.xpath('//meta').each do |m|
        if m.attribute('property') && m.attribute('property').to_s.match(/^og:(.+)$/i)
          m_content = m.attribute('content').to_s.strip
          metadata_name = m.attribute('property').to_s.gsub("og:", "")
          @metadata = add_metadata(@metadata, metadata_name, m_content)
          case metadata_name
            when *attrs_list
              self.instance_variable_set("@#{metadata_name}", m_content) unless m_content.empty?
            when "image"
              add_image(m_content)
          end
        end
      end
    end
  end

  def load_fallback
    if @body
      doc = parse_html(@body, @charset)

      if @title.to_s.empty? && doc.xpath("//head//title").size > 0
        @title = doc.xpath("//head//title").first.text.to_s.strip
      end

      @url = @src if @url.to_s.empty?

      if @description.to_s.empty? && description_meta = doc.xpath("//head//meta[@name='description']").first
        @description = description_meta.attribute("content").to_s.strip
      end

      fetch_images(doc, "//head//link[@rel='image_src']", "href") if @images.empty?
      fetch_images(doc, "//img", "src") if @images.empty?
    end
  end

  def check_images_path
    @original_images = @images.dup
    uri = Addressable::URI.parse(@src)
    imgs = @images.dup
    @images = []
    imgs.each do |img|
      if Addressable::URI.parse(img).host.nil?
        full_path = uri.join(img).to_s
        add_image(full_path)
      else
        add_image(img)
      end
    end
  end

  def add_image(image_url)
    @images << image_url unless @images.include?(image_url) || image_url.to_s.empty?
  end

  def fetch_images(doc, xpath_str, attr)
    doc.xpath(xpath_str).each do |link|
      add_image(link.attribute(attr).to_s.strip)
    end
  end

  def add_metadata(metadata_container, path, content)
    path_elements = path.split(':')
    if path_elements.size > 1
      current_element = path_elements.delete_at(0)
      path = path_elements.join(':')
      if metadata_container[current_element.to_sym]
        path_pointer = metadata_container[current_element.to_sym].last
        index_count = metadata_container[current_element.to_sym].size
        metadata_container[current_element.to_sym][index_count - 1] = add_metadata(path_pointer, path, content)
        metadata_container
      else
        metadata_container[current_element.to_sym] = []
        metadata_container[current_element.to_sym] << add_metadata({}, path, content)
        metadata_container
      end
    else
      metadata_container[path.to_sym] ||= []
      metadata_container[path.to_sym] << {'_value'.to_sym => content}
      metadata_container
    end
  end

  def parse_html(body, charset)
    unless charset
      doc = Nokogiri.parse(body.scrub)
      charset = guess_encoding(doc)
    end
    Nokogiri::HTML(body, nil, charset)
  end

  def guess_encoding(doc)
    charset = doc.xpath('//meta/@charset').first
    return charset.value.to_s if charset

    charset = doc.xpath('//meta').each do |m|
      if m.attribute('http-equiv') && m.attribute('content') && m.attribute('http-equiv').value.casecmp('Content-Type')
        return m.attribute('content').value.split('charset=').last.strip
      end
    end

    'UTF-8'
  end

end
