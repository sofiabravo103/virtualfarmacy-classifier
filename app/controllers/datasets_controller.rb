class DatasetsController < ApplicationController
  before_action :authenticate_user!

  def index
    @datasets = Dataset.all
    @total_annotated = @datasets.collect {|d| d.annotated_tweets.size}.reduce(:+)
    winner_amount = 0
    @winners = []
    User.all.each do |u|
      ann = u.annotations
      if ann > winner_amount
        winner_amount = ann
        @winners = [u.id]
      elsif ann == winner_amount
        @winners << u.id
      end
    end
  end

  def edit
    @dataset = Dataset.find(params[:id])
    # not admin
    unless current_user.has_role? :admin or current_user.email == @dataset.user.email
      render(:file => File.join(Rails.root, 'public/403.html'), :status => 403, :layout => false)
    end

    # dataset is done
    unless @tweet = @dataset.get_unannotated_tweet
      redirect_to dataset_path(@dataset.id)
    end
  end

  def update
    @dataset = Dataset.find(params[:id])
    unless current_user.has_role? :admin or current_user.email == @dataset.user.email
      render(:file => File.join(Rails.root, 'public/403.html'), :status => 403, :layout => false)
    end
    @tweet = Tweet.find(params[:dataset][:tweet_id])
    @tweet.update(annotation: params[:dataset][:annotation])
    @dataset.update(updated_at: DateTime.now)
    if params[:dataset][:annotation] != ""
      redirect_to edit_dataset_path(@dataset.id)
    else
      redirect_to dataset_path(@dataset.id)
    end
  end

  def destroy
    unless current_user.has_role? :admin
      render(:file => File.join(Rails.root, 'public/403.html'), \
        :status => 403, :layout => false)
      return
    end
    @dataset = Dataset.find(params[:id])
    @dataset.destroy!
    redirect_to datasets_path
  end

  def show
    @dataset = Dataset.find(params[:id])
  end

  def download
    unless current_user.has_role? :admin
      render(:file => File.join(Rails.root, 'public/403.html'), \
        :status => 403, :layout => false)
      return
    end
    @dataset = Dataset.find(params[:id])
    time = DateTime.now.in_time_zone("Caracas").strftime('%s')
    send_data @dataset.to_csv,
      filename: "annotated_export_#{time}.csv",
      :type => 'text/csv',
      disposition: 'attachment'
  end

  def download_all
    unless current_user.has_role? :admin
      render(:file => File.join(Rails.root, 'public/403.html'), \
        :status => 403, :layout => false)
      return
    end

    time = DateTime.now.in_time_zone("Caracas").strftime('%s')
    exports = ''
    Dataset.all.each do |dataset|
      exports << dataset.to_csv
    end

    send_data exports,
      filename: "annotated_export_#{time}.csv",
      :type => 'text/csv',
      disposition: 'attachment'
  end

  def new
    unless current_user.has_role? :admin
      render(:file => File.join(Rails.root, 'public/403.html'), \
        :status => 403, :layout => false)
      return
    end
    @dataset = Dataset.new
    @available_users = User.all
  end

  def create
    unless current_user.has_role? :admin
      render(:file => File.join(Rails.root, 'public/403.html'), \
        :status => 403, :layout => false)
      return
    end
    if params[:dataset].include? :csv and params[:dataset].include? :user
      @owner = User.find_by(email: params[:dataset][:user])
      @dataset = Dataset.create!(user: @owner)

      good_text = params[:dataset][:csv].read.encode('UTF-8', 'binary', \
        invalid: :replace, undef: :replace, replace: '').gsub("u'","'")

      tweets = []

      good_text.each_line do |line|
        tweet_parsed_info = {}
        text = line.tr("\n",'').split(';').each do |item|
          key, *value = item.split(':', 2)
          tweet_parsed_info[key] = value[0] if key
        end
        tweets << tweet_parsed_info
      end
      bulk_insert_tweets(tweets)

      redirect_to dataset_path(@dataset.id)
    else
    end
  end

  private

  def generate_csv

  end

  def bulk_insert_tweets(tweets)
    ActiveRecord::Base.transaction do
      tweets.each do |t_info|
        t = Tweet.new(
          dataset: @dataset,
          text: t_info['text'],
          twitter_id: t_info['id']
        )
        t.save
      end
    end
  end

end
