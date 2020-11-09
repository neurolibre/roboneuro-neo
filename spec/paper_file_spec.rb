require_relative "./spec_helper.rb"

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
  end

  describe "#bibtex_entries" do
    it "should read bibtex file" do
      expect(subject).to receive(:bibtex_path).and_return(fixture("paper.bib"))
      bibtex_entries = subject.bibtex_entries
      expect(bibtex_entries.size).to eq(5)
      expect(bibtex_entries.first.title.value).to eq("The NumPy Array: A Structure for Efficient Numerical Computation")
    end

    it "should be empty if errors parsing the file" do
      expect(BibTeX).to receive(:open).and_raise BibTeX::ParseError
      expect(subject.bibtex_entries).to eq([])
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
      allow(Find).to receive(:find).with("/repo/path/").and_return(["lib/papers.pdf", "./docs", "app"])

      paper_file = PaperFile.find("/repo/path/")

      expect(paper_file).to be_kind_of PaperFile
      expect(paper_file.paper_path).to be_nil
    end
  end

end