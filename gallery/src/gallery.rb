#!/usr/bin/env ruby

# Only ruby stdlib "libraries" here; https://ruby-doc.org/stdlib-2.7.0/ has a list of what's available.
require 'erb'
require 'pathname'

class GalleryTemplate < Struct.new(
  :buildkite_pipeline_name,
  :gallery_path_prefix,
  :canonical_branch_images_dir,
  :canonical_repo_and_branch,
  :triggering_commit,
  :triggering_commit_images_dir,
  :triggering_repo_and_branch,
  keyword_init: true,
)
  Image = Struct.new(:url, :filename, :title, keyword_init: true)

  def render
    erb = File.read(File.join(__dir__, 'gallery.html.erb'))
    ERB.new(erb).result(binding)
  end

  private

  def triggering_commit_images
    @triggering_commit_images ||= images_for_path(triggering_commit_images_dir)
  end

  def canonical_branch_images
    @canonical_branch_images ||= images_for_path(canonical_branch_images_dir)
  end

  def gallery_images
    return @gallery_images if @gallery_images

    # Make a hash of { filename => Image }
    canonical_by_name =
      canonical_branch_images.map { |image| [ image.filename, image ] }.to_h

    # Make an array of pairs of Commit and Comparison images.
    @gallery_images = triggering_commit_images.map do |triggering_commit_image|
      [ triggering_commit_image, canonical_by_name.delete(triggering_commit_image.filename) ]
    end
  end

  def has_canonical_branch?
    !canonical_branch_images.empty?
  end

  ### Helpers

  def images_for_path(path)
    Dir["#{path}/**/*.png"].map do |filename|
      Image.new(
        url: "#{gallery_path_prefix}#{nice_path(filename)}",
        filename: File.basename(filename),
        title: File.basename(filename, '.png'),
      )
    end
  end

  # "./foo/bar" => "foo/bar"
  def nice_path(relative_path)
    Pathname
      .new(File.expand_path(relative_path))
      .relative_path_from(Dir.pwd)
      .to_s
  end
end

env_vars = %w(
  buildkite_pipeline_name
  gallery_path_prefix
  canonical_branch_images_dir
  canonical_repo_and_branch
  triggering_commit
  triggering_commit_images_dir
  triggering_repo_and_branch
)
template = GalleryTemplate.new(
  env_vars.map {|var| [var.to_sym, ENV.fetch(var)] }.to_h
)
File.write(ARGV.fetch(0), template.render)
