require_relative "./spec_helper.rb"
require 'tmpdir'

describe PaperFile do

  subject do
    described_class.new("./doc/paper.md")
  end

  describe "Initialization" do
    it "should initialize paper_path" do
      expect(subject.paper_path).to eq("./doc/paper.md")
      expect(subject.bibtex_error).to be_nil
    end

    it "should add error if no path" do
      paper_file = PaperFile.new
      expect(paper_file.bibtex_error).to_not be_nil
    end
  end

  describe "#metadata path" do
    it "should be the paper path if paper is not a .tex file" do
      expect(subject.metadata_path).to eq(subject.paper_path)
      expect(subject.metadata_path).to eq("./doc/paper.md")
    end

    it "should be a paper.yml file if paper is a .tex file" do
      paper = PaperFile.new("./docs/paper.tex")
      expect(paper.metadata_path).to eq("./docs/paper.yml")
    end
  end

  describe "#bibtex_filename" do
    it "should read the metadata file" do
      expect(YAML).to receive(:load_file).with("./doc/paper.md").and_return({'bibliography' => 'paper.bib'})
      expect(subject.bibtex_filename).to eq("paper.bib")
      expect(subject.bibtex_error).to be_nil
    end

    it "should be nil if can't read the metadata file" do
      expect(subject.bibtex_filename).to be_nil
      expect(subject.bibtex_error).to_not be_nil
    end

    it "should set bibtex_error if no bibtex_file" do
      expect(YAML).to receive(:load_file).with("./doc/paper.md").and_return({'bib' => 'paper.bib'})
      expect(subject.bibtex_filename).to be_nil
      expect(subject.bibtex_error).to_not be_nil
    end
  end

  describe "#bibtex_path" do
    it "should return the path of the bib file from the paper's metadata" do
      expect(YAML).to receive(:load_file).with("./doc/paper.md").and_return({'bibliography' => 'references.bib'})
      expect(subject.bibtex_path).to eq("./doc/references.bib")
    end

    it "should clamp the bibliography filename to its basename to prevent path traversal" do
      expect(YAML).to receive(:load_file).with("./doc/paper.md").and_return({'bibliography' => '../../../../etc/hosts'})
      expect(subject.bibtex_path).to eq("./doc/hosts")
    end

    it "should strip leading directories from the bibliography filename" do
      expect(YAML).to receive(:load_file).with("./doc/paper.md").and_return({'bibliography' => 'subdir/refs.bib'})
      expect(subject.bibtex_path).to eq("./doc/refs.bib")
    end
  end

  describe "#bib" do
    it "should read bibtex file" do
      allow(subject).to receive(:bibtex_paths).and_return([fixture("paper.bib")])
      bib = subject.bib
      expect(bib.data.size).to eq(6)
      expect(bib.errors).to be_empty
      expect(bib.data.first.title.value).to eq("The NumPy Array: A Structure for Efficient Numerical Computation")
    end

    it "should find lexical errors" do
      allow(subject).to receive(:bibtex_paths).and_return([fixture("paper_with_errors.bib")])

      level = BibTeX.log.level
      BibTeX.log.level = "ERROR"
      bib = subject.bib
      BibTeX.log.level = level

      expect(bib.errors).to_not be_empty
      expect(bib.errors.size).to eq(2)
      expect(bib.errors.first.content).to match(/@article{numpy/)
      expect(bib.errors.last.content).to match(/@article{matplotlib/)
    end
  end

  describe "#bibtex_entries" do
    it "should read bibtex file" do
      allow(subject).to receive(:bibtex_paths).and_return([fixture("paper.bib")])
      bibtex_entries = subject.bibtex_entries
      expect(bibtex_entries.size).to eq(6)
      expect(bibtex_entries.first.title.value).to eq("The NumPy Array: A Structure for Efficient Numerical Computation")
      expect(bibtex_entries.first.author.value).to eq("van der Walt, S. and Colbert, S. C. and Varoquaux, G.")
      expect(bibtex_entries.first.doi.value).to eq("10.1109/MCSE.2011.37")
      expect(subject.bibtex_error).to be_nil
    end

    it "should parse latex except for doi field" do
      allow(subject).to receive(:bibtex_paths).and_return([fixture("paper.bib")])
      bibtex_entries = subject.bibtex_entries
      expect(bibtex_entries.size).to eq(6)
      expect(bibtex_entries.last.title.value).to eq("The LaTeX test: A Structure")
      expect(bibtex_entries.last.author.value).to eq("PArsed, S. and Van–Hall, S. C. and Varo, G.")
      expect(bibtex_entries.last.doi.value).to eq("10.1109/MCSE.2011--37")
      expect(bibtex_entries.last.pages.value).to eq("22–30")
      expect(subject.bibtex_error).to be_nil
    end

    it "should be empty if errors parsing the file" do
      allow(subject).to receive(:bibtex_paths).and_return([fixture("paper.bib")])
      expect(BibTeX).to receive(:open).and_raise BibTeX::ParseError
      expect(subject.bibtex_entries).to eq([])
    end

    it "should set bibtex_error if lexical errors found" do
      allow(subject).to receive(:bibtex_paths).and_return([fixture("paper_with_errors.bib")])

      level = BibTeX.log.level
      BibTeX.log.level = "ERROR"
      bibtex_entries = subject.bibtex_entries
      BibTeX.log.level = level

      expect(bibtex_entries.size).to eq(4)
      expect(subject.bibtex_error).to_not be_nil
      expect(subject.bibtex_error).to match(/@article{numpy/)
      expect(subject.bibtex_error).to match(/@article{matplotlib/)
    end
  end

  describe ".find" do
    it "should return a PaperFile initialized with the paper path if present" do
      expect(Dir).to receive(:exist?).with("/repo/path/").and_return(true)
      expect(Find).to receive(:find).with("/repo/path/").and_return(["lib/papers", "./docs/paper.md", "app"])

      paper_file = PaperFile.find("/repo/path/")

      expect(paper_file).to be_kind_of PaperFile
      expect(paper_file.paper_path).to eq("./docs/paper.md")
    end

    it "should return a nil PaperFile if search_path does not exists" do
      expect(Dir).to receive(:exist?).with("/repo/path/").and_return(false)

      paper_file = PaperFile.find("/repo/path/")

      expect(paper_file).to be_kind_of PaperFile
      expect(paper_file.paper_path).to be_nil
    end

    it "should return a nil PaperFile if no paper file found" do
      expect(Dir).to receive(:exist?).with("/repo/path/").and_return(true)
      allow(Find).to receive(:find).with("/repo/path/").and_return(["lib/papers.pdf", "lib/other_paper.md", "./docs", "app"])

      paper_file = PaperFile.find("/repo/path/")

      expect(paper_file).to be_kind_of PaperFile
      expect(paper_file.paper_path).to be_nil
    end
  end

  describe "MyST papers" do
    around(:each) do |example|
      Dir.mktmpdir do |dir|
        @clone = dir
        example.run
      end
    end

    def myst_paper(frontmatter, project, bibs = { "paper.bib" => File.read(fixture("paper.bib")) })
      File.write(File.join(@clone, "paper.md"), "---\n#{frontmatter}---\n\n# Introduction\n")
      File.write(File.join(@clone, "myst.yml"), "version: 1\nproject:\n#{project}")
      bibs.each { |name, content| File.write(File.join(@clone, name), content) }

      PaperFile.find(@clone)
    end

    it "should read the bibliography declared in myst.yml when the frontmatter omits it" do
      paper = myst_paper("title: An OCT paper\n", "  bibliography:\n    - paper.bib\n")

      expect(paper.bibtex_entries.size).to eq(6)
      expect(paper.bibtex_error).to be_nil
    end

    it "should merge the entries of every bibliography declared in myst.yml" do
      second_bib = "@article{extra,\n  title = {An extra reference},\n  doi = {10.1000/extra}\n}\n"
      paper = myst_paper("title: An OCT paper\n",
                         "  bibliography:\n    - paper.bib\n    - extra.bib\n",
                         { "paper.bib" => File.read(fixture("paper.bib")), "extra.bib" => second_bib })

      expect(paper.bibtex_entries.size).to eq(7)
      expect(paper.bibtex_entries.map { |entry| entry.key.to_s }).to include("numpy", "extra")
      expect(paper.bibtex_error).to be_nil
    end

    it "should report a missing bibliography instead of raising when neither file declares one" do
      paper = myst_paper("title: An OCT paper\n", "  title: An OCT project\n")

      expect { paper.bibtex_entries }.to_not raise_error
      expect(paper.bibtex_entries).to eq([])
      expect(paper.bibtex_error).to match(/bibliography/i)
    end
  end

  describe "#text" do
    it "should return the contents of the paper file" do
      file = OpenStruct.new(read: "paper content")
      expect(File).to receive(:open).with("./path/to/paper.md").and_return(file)

      paper = PaperFile.new("./path/to/paper.md")
      expect(paper.text).to eq("paper content")
    end

    it "should return '' if paper_path is not present" do
      paper = PaperFile.new(nil)
      expect(paper.text).to eq("")

      paper = PaperFile.new("")
      expect(paper.text).to eq("")
    end
  end
end