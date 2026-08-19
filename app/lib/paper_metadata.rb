require 'yaml'

# Resolves a paper's metadata, preferring the paper's own frontmatter and
# falling back to the MyST project configuration (myst.yml) when a key is
# absent from it. MyST papers commonly declare project-wide metadata such as
# the bibliography in myst.yml rather than repeating it in every document.
class PaperMetadata

  MYST_CONFIG_FILENAME = 'myst.yml'.freeze

  # metadata_path - the paper's frontmatter source (paper.md, or paper.yml for
  #                 LaTeX submissions).
  # search_root   - the directory myst.yml lookup may walk up to, normally the
  #                 root of the cloned repository. Without it the lookup is
  #                 confined to the paper's own directory, so it can never
  #                 wander outside the tree the caller intended.
  def initialize(metadata_path, search_root: nil)
    @metadata_path = metadata_path
    @search_root = search_root
  end

  # Always returns an Array: frontmatter states single values as scalars while
  # myst.yml states several of the same keys as lists, and callers should not
  # have to care which file answered.
  def values_for(key)
    value = frontmatter[key]
    value = myst_project[key] if value.nil?

    Array(value)
  end

  private

  def frontmatter
    @frontmatter ||= load_yaml(@metadata_path)
  end

  def myst_project
    return @myst_project if defined?(@myst_project)

    project = load_yaml(myst_config_path)['project']
    @myst_project = project.is_a?(Hash) ? project : {}
  end

  def myst_config_path
    directory = searchable_directories.find do |dir|
      File.file?(File.join(dir, MYST_CONFIG_FILENAME))
    end

    File.join(directory, MYST_CONFIG_FILENAME) unless directory.nil?
  end

  # The paper's directory first, then its ancestors up to and including
  # search_root: myst.yml lives at the project root while the paper itself is
  # often nested (content/paper.md, paper/paper.md ...).
  def searchable_directories
    start = File.expand_path(File.dirname(@metadata_path))
    return [start] if @search_root.nil?

    root = File.expand_path(@search_root)
    directories = []
    directory = start

    while directory == root || directory.start_with?("#{root}#{File::SEPARATOR}")
      directories << directory
      break if directory == root

      parent = File.dirname(directory)
      break if parent == directory
      directory = parent
    end

    directories
  end

  def load_yaml(path)
    return {} if path.nil?

    loaded = YAML.load_file(path) rescue nil
    loaded.is_a?(Hash) ? loaded : {}
  end
end
