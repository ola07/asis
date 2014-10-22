require 'rails_helper'

describe MrssPhotosImporter do
  it { should be_retryable true }
  it { should be_unique }

  describe "#perform" do
    before do
      MrssPhoto.gateway.delete_index!
      MrssPhoto.create_index!
    end

    let(:importer) { MrssPhotosImporter.new }
    let(:mrss_url) { 'http://some.mrss.url/feed.xml' }
    let(:feed) { double(Feedjira::Parser::Oasis::Mrss, entries: []) }

    it "should fetch the photos from the MRSS feed" do
      expect(Feedjira::Feed).to receive(:fetch_and_parse).with(mrss_url, MrssPhotosImporter::FEEDJIRA_OPTIONS) { feed }
      importer.perform(mrss_url)
    end

    context 'when MRSS photo entries are returned' do
      let(:mrss_url) { 'http://some.mrss.url/feed.xml' }
      let(:photos) do
        photo1 = Hashie::Mash.new(entry_id: "guid1",
                                  title: 'first photo',
                                  summary: 'summary for first photo',
                                  published: Time.parse("2014-10-22 14:24:00Z"),
                                  thumbnail_url: "http://photo_thumbnail1",
                                  url: 'http://photo1')
        photo2 = Hashie::Mash.new(entry_id: "guid2",
                                  title: 'second photo',
                                  summary: 'summary for second photo',
                                  published: Time.parse("2014-10-22 14:24:00Z"),
                                  thumbnail_url: "http://photo_thumbnail2",
                                  url: 'http://photo2')
        [photo1, photo2]
      end

      let(:feed) { double(Feedjira::Parser::Oasis::Mrss, entries: photos) }

      before do
        expect(Feedjira::Feed).to receive(:fetch_and_parse).with(mrss_url, MrssPhotosImporter::FEEDJIRA_OPTIONS) { feed }
      end

      it "should store and index them" do
        importer.perform(mrss_url)
        first = MrssPhoto.find("guid1")
        expect(first.id).to eq('guid1')
        expect(first.mrss_url).to eq(mrss_url)
        expect(first.title).to eq('first photo')
        expect(first.description).to eq('summary for first photo')
        expect(first.taken_at).to eq(Date.parse("2014-10-22"))
        expect(first.popularity).to eq(0)
        expect(first.url).to eq('http://photo1')
        expect(first.thumbnail_url).to eq('http://photo_thumbnail1')
        second = MrssPhoto.find("guid2")
        expect(second.id).to eq('guid2')
        expect(second.mrss_url).to eq(mrss_url)
        expect(second.title).to eq('second photo')
        expect(second.description).to eq('summary for second photo')
        expect(second.taken_at).to eq(Date.parse("2014-10-22"))
        expect(second.popularity).to eq(0)
        expect(second.url).to eq('http://photo2')
        expect(second.thumbnail_url).to eq('http://photo_thumbnail2')
      end
    end

    context 'when photo cannot be created' do
      let(:photos) do
        photo1 = Hashie::Mash.new(entry_id: "guid1",
                                  title: 'first photo',
                                  summary: 'summary for first photo',
                                  published: "this will break it",
                                  thumbnail_url: "http://photo_thumbnail1",
                                  url: 'http://photo1')
        photo2 = Hashie::Mash.new(entry_id: "guid2",
                                  title: 'second photo',
                                  summary: 'summary for second photo',
                                  published: Time.parse("2014-10-22 14:24:00Z"),
                                  thumbnail_url: "http://photo_thumbnail2",
                                  url: 'http://photo2')
        [photo1, photo2]
      end

      let(:feed) { double(Feedjira::Parser::Oasis::Mrss, entries: photos) }

      before do
        expect(Feedjira::Feed).to receive(:fetch_and_parse).with(mrss_url, MrssPhotosImporter::FEEDJIRA_OPTIONS) { feed }
      end

      it "should log the issue and move on to the next photo" do
        expect(Rails.logger).to receive(:warn)
        importer.perform(mrss_url)

        expect(MrssPhoto.find("guid2")).to be_present
      end
    end

    context 'when photo already exists in the index' do
      let(:photos) do
        photo1 = Hashie::Mash.new(entry_id: "already exists",
                                  title: 'new title',
                                  summary: 'new summary',
                                  published: Time.parse("2014-10-22 14:24:00Z"),
                                  thumbnail_url: "http://photo_thumbnail1",
                                  url: 'http://photo1')

        [photo1]
      end

      let(:feed) { double(Feedjira::Parser::Oasis::Mrss, entries: photos) }

      before do
        expect(Feedjira::Feed).to receive(:fetch_and_parse).with(mrss_url, MrssPhotosImporter::FEEDJIRA_OPTIONS) { feed }
        MrssPhoto.create(id: "already exists", mrss_url: 'some url', tags: %w(tag1 tag2), title: 'initial title', description: 'initial description', taken_at: Date.current, popularity: 0, url: "http://mrssphoto2", thumbnail_url: "http://mrssphoto_thumbnail2", album: 'album3')
      end

      it "should ignore it" do
        importer.perform(mrss_url)

        already_exists = MrssPhoto.find("already exists")
        expect(already_exists.album).to eq("album3")
        expect(already_exists.popularity).to eq(0)
      end
    end

    context 'when MRSS feed generates some error' do
      before do
        expect(Feedjira::Feed).to receive(:fetch_and_parse).and_raise Exception
      end

      it 'should log a warning and continue' do
        expect(Rails.logger).to receive(:warn)
        importer.perform('someurl')
      end
    end

  end

  describe ".refresh" do
    before do
      allow(MrssProfile).to receive(:find_each).and_yield(double(MrssProfile, id: 'http://some/mrss.url/feed.xml1')).and_yield(double(MrssProfile, id: 'http://some/mrss.url/feed.xml2'))
    end

    it 'should enqueue importing the photos' do
      MrssPhotosImporter.refresh
      expect(MrssPhotosImporter).to have_enqueued_job('http://some/mrss.url/feed.xml1')
      expect(MrssPhotosImporter).to have_enqueued_job('http://some/mrss.url/feed.xml1')
    end
  end
end