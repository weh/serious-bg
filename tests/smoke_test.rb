require 'test/unit'
require "rack/test"
require 'feed_validator/assertions'
require 'webmock/test_unit'
require "net/http"
require 'typhoeus'

OUTER_APP = Rack::Builder.parse_file('config.ru').first

class SmokeTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def setup
    stub_request(:head, /download.binaergewitter.de.*/).to_return(:status => 200, :body => "", :headers => {'Content-Length' => '123456'})
  end

  def app
    OUTER_APP
  end

  def test_homepage_is_a_200
    get "/"
    assert last_response.ok?
  end

  def test_categories_is_a_200
    ['all', 'talk', 'westcoast', 'spezial'].each do |category|
      get "/categories/#{category}"
      assert last_response.ok?
    end
  end

  def test_feed_validates
    get "/podcast_feed/all/itunes/rss.xml"
    WebMock.allow_net_connect!
    assert_valid_feed(last_response.body)
    WebMock.disable_net_connect!
  end

  def test_mp3_feed_works
    get "/podcast_feed/all/mp3/rss.xml"
    assert last_response.ok?
  end

  def test_mp3_feed_works_with_feed_size
    [1,2,3,4,5].each do |number|
      get "/podcast_feed/all/mp3/rss.xml?feed_size=#{number}"
      assert last_response.ok?
      assert_equal number, last_response.body.scan('<item>').size
    end
  end

  def test_mp3_feed_works_with_feed_size_and_page_size
    last_id_set = []
    [1,2,3,4,5].each do |number|
      get "/podcast_feed/all/mp3/rss.xml?feed_size=2&page=#{number}"
      assert last_response.ok?
      current_id_set = last_response.body.scan(/<id>\s*(.*)\s*<\/id>/i).flatten
      assert_empty current_id_set & last_id_set
      last_id_set = current_id_set
    end
  end

  def test_mp3_feed_has_a_next_link
    get "/podcast_feed/all/mp3/rss.xml?feed_size=2&page=2"
    assert last_response.ok?
    # There is a next link
    assert_include last_response.body, '/podcast_feed/all/mp3/rss.xml?feed_size=2&amp;page=3'
  end


  def test_talk_category_feed_works
    get "/podcast_feed/talk/m4a/rss.xml"
    assert last_response.ok?
  end

  def test_spezial_category_feed_works
    get "/podcast_feed/spezial/m4a/rss.xml"
    assert last_response.ok?
  end

  def test_random_crap_fails
    get "/lol/catpoop.php"
    assert !last_response.ok?
  end

  def test_that_all_posts_on_the_archive_page_work
    get "/archives"
    last_response.body.scan(/a href=["'](\/2.*)["']>/).each do |match|
      get match[0]
      assert last_response.ok?
    end
  end

  def test_archive_categories_is_a_200
    ['all', 'talk', 'westcoast', 'spezial'].each do |category|
      get "/archives/categories/#{category}"
      assert last_response.ok?
    end
  end

  def test_that_all_episodes_can_be_downloaded
    WebMock.allow_net_connect!
    hydra = Typhoeus::Hydra.hydra
    requests = []
    Serious::Article.all.each do |post|
      post.audioformats.each do |format, link|
        req = Typhoeus::Request.new(link, {:method => :head})
        requests << req
        hydra.queue req
      end
    end
    hydra.run
    requests.each do |req|
      assert req.response.success?, "Audio file was not available: #{req.url}"
    end
    WebMock.disable_net_connect!
  end

  def test_the_podcast_is_live_at_xenim
    dataDump = File.new(File.expand_path("../api_response/binaergewitter_is_live.json", __FILE__), "r")
    stub_request(:get, "http://feeds.streams.xenim.de/live/binaergewitter/json/").to_return(dataDump)
    blog = Serious.new
    blog.settings.xenim_response_time = Time.now - 20 # don't use the cached data!

    assert_equal(true, blog.helpers.is_live?)
  end

  def test_the_podcast_is_not_live_at_xenim
    dataDump = File.new(File.expand_path("../api_response/binaergewitter_is_not_live.json", __FILE__), "r")
    stub_request(:get, "http://feeds.streams.xenim.de/live/binaergewitter/json/").to_return(dataDump)
    blog = Serious.new
    blog.settings.xenim_response_time = Time.now - 20 # don't use the cached data!

    assert_equal(false, blog.helpers.is_live?)
  end

  def test_the_xenim_api_is_offline
    stub_request(:get, "http://feeds.streams.xenim.de/live/binaergewitter/json/").to_return(:status => [404, "Not Found"])
    blog = Serious.new
    blog.settings.xenim_response_time = Time.now - 20 # don't use the cached data!

    assert_equal(false, blog.helpers.is_live?)
  end

  def test_the_xenim_api_timedout
    stub_request(:get, "http://feeds.streams.xenim.de/live/binaergewitter/json").to_timeout
    blog = Serious.new
    blog.settings.xenim_response_time = Time.now - 20 # don't use the cached data!

    assert_equal(false, blog.helpers.is_live?)
  end

  def test_live_preview_view
    dataDump = File.new(File.expand_path("../api_response/binaergewitter_is_not_live.json", __FILE__), "r")
    stub_request(:get, "http://feeds.streams.xenim.de/live/binaergewitter/json/").to_return(dataDump)
    blog = Serious.new
    blog.settings.xenim_response_time = Time.now - 20 # don't use the cached data!

    get "/"
    assert last_response.ok?
  end
end
