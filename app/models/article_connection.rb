# Connect to an external API to get some articles
class ArticleConnection
  # Create an initial connection to the API
  def initialize
  end

  def ready?
  end

  # Fetch a single article from the external API
  def retrieve_single_article db, id
    puts db + id
  end

  def send_search search_opts
    puts search_opts
  end

end
