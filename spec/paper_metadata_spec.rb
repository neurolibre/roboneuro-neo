require_relative "./spec_helper.rb"
require 'tmpdir'

describe PaperMetadata do

  # These specs write real files instead of mocking YAML, because the behavior
  # under test is largely about locating myst.yml on disk.
  around(:each) do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  def write_paper(frontmatter)
    path = File.join(@root, "paper.md")
    File.write(path, "---\n#{frontmatter}---\n\n# Introduction\n")
    path
  end

  def write_myst(project, dir: @root)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "myst.yml"), "version: 1\nproject:\n#{project}")
  end

  describe "reading the paper's frontmatter" do
    it "should return the value from the paper's frontmatter" do
      paper = write_paper("bibliography: refs.bib\n")

      expect(described_class.new(paper).values_for('bibliography')).to eq(["refs.bib"])
    end
  end

  describe "falling back to myst.yml" do
    it "should read the key from myst.yml when the frontmatter omits it" do
      paper = write_paper("title: A paper with no bibliography key\n")
      write_myst("  bibliography:\n    - paper.bib\n")

      expect(described_class.new(paper, search_root: @root).values_for('bibliography')).to eq(["paper.bib"])
    end

    it "should prefer the frontmatter over myst.yml when both declare the key" do
      paper = write_paper("bibliography: frontmatter.bib\n")
      write_myst("  bibliography:\n    - myst.bib\n")

      expect(described_class.new(paper, search_root: @root).values_for('bibliography')).to eq(["frontmatter.bib"])
    end

    it "should return every value when myst.yml declares a list" do
      paper = write_paper("title: A paper with several bibliographies\n")
      write_myst("  bibliography:\n    - one.bib\n    - two.bib\n")

      expect(described_class.new(paper, search_root: @root).values_for('bibliography')).to eq(["one.bib", "two.bib"])
    end

    it "should find myst.yml in an ancestor directory of the paper" do
      nested = File.join(@root, "content", "article")
      FileUtils.mkdir_p(nested)
      paper = File.join(nested, "paper.md")
      File.write(paper, "---\ntitle: A nested paper\n---\n")
      write_myst("  bibliography:\n    - paper.bib\n")

      expect(described_class.new(paper, search_root: @root).values_for('bibliography')).to eq(["paper.bib"])
    end

    it "should not look for myst.yml above the search root" do
      outside = File.join(@root, "outside")
      clone = File.join(outside, "clone")
      FileUtils.mkdir_p(clone)
      paper = File.join(clone, "paper.md")
      File.write(paper, "---\ntitle: A paper whose project config sits too high\n---\n")
      write_myst("  bibliography:\n    - unreachable.bib\n", dir: outside)

      expect(described_class.new(paper, search_root: clone).values_for('bibliography')).to be_empty
    end

    it "should not look beyond the paper's directory without a search root" do
      nested = File.join(@root, "content")
      FileUtils.mkdir_p(nested)
      paper = File.join(nested, "paper.md")
      File.write(paper, "---\ntitle: A nested paper\n---\n")
      write_myst("  bibliography:\n    - paper.bib\n")

      expect(described_class.new(paper).values_for('bibliography')).to be_empty
    end
  end

  describe "when the key is nowhere to be found" do
    it "should be empty if neither the frontmatter nor myst.yml declare it" do
      paper = write_paper("title: A paper with no bibliography anywhere\n")
      write_myst("  title: A project with no bibliography\n")

      expect(described_class.new(paper, search_root: @root).values_for('bibliography')).to be_empty
    end

    it "should be empty if there is no myst.yml at all" do
      paper = write_paper("title: A paper with no project config\n")

      expect(described_class.new(paper, search_root: @root).values_for('bibliography')).to be_empty
    end

    it "should be empty if the paper's frontmatter is unparseable" do
      paper = File.join(@root, "paper.md")
      File.write(paper, "---\ntitle: 'unterminated\n\tbibliography: [\n---\n")
      write_myst("  bibliography:\n    - paper.bib\n")

      expect(described_class.new(paper, search_root: @root).values_for('bibliography')).to eq(["paper.bib"])
    end

    it "should be empty if myst.yml is unparseable" do
      paper = write_paper("title: A paper with a broken project config\n")
      File.write(File.join(@root, "myst.yml"), "project:\n  bibliography: [\n\t- broken\n")

      expect(described_class.new(paper, search_root: @root).values_for('bibliography')).to be_empty
    end
  end
end
