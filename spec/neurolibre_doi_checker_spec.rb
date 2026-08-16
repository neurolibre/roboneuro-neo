require_relative "spec_helper.rb"

# NeuroLibre-specific characterization of DOIChecker's Crossref resilience.
#
# These behaviours are NeuroLibre additions to an otherwise upstream-owned
# class, and the 2026-08 upstream merge demonstrated why they need their own
# assertions: upstream restructured `check_dois`, moving the title-only branch
# into `handle_missing_doi`, and the inter-lookup throttle was silently lost in
# the conflict resolution. Nothing in the suite went red. The gap was found by
# reading the diff, which is not a control you can rely on twice.
#
# Deliberately a separate file from upstream's spec/doi_checker_spec.rb:
# editing that one would add it to the set of files both forks modify, and so
# create a merge conflict on every future upstream sync.
describe DOIChecker do

  # Crossref's anonymous pool is roughly 1 request/sec, shared. A bib file with
  # many DOI-less entries fires one lookup per entry, back to back, and trips it
  # -- which surfaces to the author as CROSSREF-ERROR noise rather than a clean
  # failure. These two guards are why that does not happen.
  describe "Crossref rate-limit protections" do

    let(:entry) do
      double(has_field?: false, title: double(value: "Some paper title", to_s: "Some paper title"))
    end

    describe "the polite-pool configuration" do
      # `Serrano.configuration` yields rather than returning (serrano-1.7
      # lib/serrano/helpers/configuration.rb:5), so the value is read through
      # the generated class-level reader, not off the return value.
      it "should register a mailto so requests leave the anonymous pool" do
        expect(Serrano.mailto.to_s).to_not be_empty
      end
    end

    describe "the inter-lookup throttle" do
      subject { described_class.new([]) }

      it "should define a non-zero delay between sequential lookups" do
        expect(DOIChecker::CROSSREF_LOOKUP_DELAY).to be > 0
      end

      # The load-bearing one. If a refactor moves the title-only branch again
      # and leaves the sleep behind, this fails.
      it "should sleep once per DOI-less entry it looks up" do
        allow(subject).to receive(:crossref_lookup).and_return(nil)
        expect(subject).to receive(:sleep).with(DOIChecker::CROSSREF_LOOKUP_DELAY).once
        subject.handle_missing_doi(entry)
      end

      it "should still throttle when Crossref errors" do
        allow(subject).to receive(:crossref_lookup).and_return("CROSSREF-ERROR")
        expect(subject).to receive(:sleep).with(DOIChecker::CROSSREF_LOOKUP_DELAY).once
        subject.handle_missing_doi(entry)
      end

      it "should still throttle when a candidate DOI is found" do
        allow(subject).to receive(:crossref_lookup).and_return("10.1234/abcd")
        expect(subject).to receive(:sleep).with(DOIChecker::CROSSREF_LOOKUP_DELAY).once
        subject.handle_missing_doi(entry)
      end
    end

    describe "the retry wrapper" do
      subject { described_class.new([]) }

      # serrano does a bare MultiJson.load(res.body) with no status check
      # (serrano-1.7 lib/serrano/request_cursor.rb:145, request.rb:78), so a
      # rate-limited or otherwise non-JSON response raises MultiJson::ParseError
      # rather than a handleable serrano error. Verified still true on the
      # serrano 1.7 that came in with the 2026-08 merge.
      it "should retry a MultiJson::ParseError before giving up" do
        allow(subject).to receive(:sleep)
        expect(Serrano).to receive(:works).exactly(DOIChecker::CROSSREF_MAX_ATTEMPTS).times
                                          .and_raise(MultiJson::ParseError.allocate)

        expect(subject.crossref_works_with_retry("a title")).to be_nil
      end

      it "should return the result without retrying when the call succeeds" do
        allow(subject).to receive(:sleep)
        expect(Serrano).to receive(:works).once.and_return({ "message" => {} })

        expect(subject.crossref_works_with_retry("a title")).to eq({ "message" => {} })
      end

      it "should report CROSSREF-ERROR to the caller when every attempt fails" do
        allow(subject).to receive(:sleep)
        allow(Serrano).to receive(:works).and_raise(MultiJson::ParseError.allocate)

        expect(subject.crossref_lookup("a title")).to eq("CROSSREF-ERROR")
      end
    end
  end
end
