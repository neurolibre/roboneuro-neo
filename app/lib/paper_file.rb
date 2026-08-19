require 'bibtex'

require_relative './paper_metadata'

class PaperFile
  attr_accessor :paper_path
  attr_accessor :bibtex_entries
  attr_accessor :bibtex_error

  def initialize(path=nil, search_root: nil)
    @paper_path = path
    @search_root = search_root
    @bibtex_error = "No paper file path" if @paper_path.nil?
  end

  def bib
    @bib ||= merged_bibliography
  end

  def bibtex_entries
    return @bibtex_entries = [] if bibtex_paths.empty?

    @bibtex_entries ||= bib.data
    @bibtex_entries.keep_if { |entry| !entry.comment? && !entry.preamble? && !entry.string? }

    unless bib.errors.empty?
      @bibtex_error = "Lexical or syntactical errors: \n\n"
      @bibtex_error += bib.errors.map(&:content).join("\n")
    end

    @bibtex_entries
  rescue BibTeX::ParseError => e
    @bibtex_error = e.message
    []
  end

  def bibtex_paths
    @bibtex_paths ||= bibtex_filenames.map { |filename| "#{File.dirname(paper_path)}/#{filename}" }
  end

  def bibtex_path
    bibtex_paths.first
  end

  # Filenames are clamped to their basename and resolved against the paper's own
  # directory, so a bibliography entry can never reach outside it.
  def bibtex_filenames
    return @bibtex_filenames unless @bibtex_filenames.nil?
    return @bibtex_filenames = [] if paper_path.nil?

    @bibtex_filenames = metadata.values_for('bibliography').
                          map { |filename| File.basename(filename.to_s) }.
                          reject { |filename| ['', '.', '..', File::SEPARATOR].include?(filename) }

    if @bibtex_filenames.empty?
      @bibtex_error = "Couldn't find bibliography entry in the paper's metadata"
    end

    @bibtex_filenames
  end

  def bibtex_filename
    bibtex_filenames.first
  end

  def metadata
    @metadata ||= PaperMetadata.new(metadata_path, search_root: @search_root)
  end

  def metadata_path
    if paper_path.end_with?('.tex')
      "#{File.dirname(paper_path)}/paper.yml"
    else
      paper_path
    end
  end

  def self.find(search_path)
    paper_path = nil

    if Dir.exist? search_path
      Find.find(search_path).each do |path|
        if path =~ /\/paper\.tex$|\/paper\.md$/
          paper_path = path
          break
        end
      end
    end

    PaperFile.new paper_path, search_root: search_path
  end

  def text
    return "" if @paper_path.nil? || @paper_path.empty?
    File.open(@paper_path).read
  end

  private

  # MyST projects may declare more than one bibliography. Their entries are
  # merged into a single bibliography so that every reference gets DOI-checked,
  # rather than only those of the first file.
  def merged_bibliography
    parsed = bibtex_paths.map { |path| parse_bib(path) }

    parsed.drop(1).each_with_object(parsed.first) do |other, merged|
      other.data.each { |entry| merged.add(entry) }
      merged.errors.concat(other.errors)
    end
  end

  def parse_bib(path)
    parsed_bib = BibTeX.open(path, filter: :latex)
    no_filter_bib = BibTeX.open(path)

    parsed_bib.data.each_with_index do |entry, i|
      entry.doi = no_filter_bib.data[i].doi if entry.is_a?(BibTeX::Entry) && entry.has_field?('doi')
    end

    parsed_bib
  end

end