require 'rubygems'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'mongo'
require 'json'
require 'mongoid'
require 'awesome_print'

include Mongo

configure do
	Mongoid.load!('mongoid.yml')
end

RECOMMENDAITONS_MAX = 5
TAG_VALUE = 1
FOLLOWEE_SONG_VALUE = 1
NEW_SONGS_COEFFICIENT = 2

class Song
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String

  has_and_belongs_to_many :users
  has_and_belongs_to_many :tags, inverse_of: nil

  validates_presence_of :name
end

class User
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String

  has_and_belongs_to_many :songs, autosave: true
  has_and_belongs_to_many :following, class_name: 'User', autosave: true

  validates_presence_of :name

  def follow!(user)
    if self.id != user.id && !self.following.include?(user)
      self.following << user
    end
  end

  def listen!(song)
    self.songs << song
  end
end

class Tag
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String

  validates_presence_of :name
end

before do
  songs_json = File.read('songs.json')
	songs_obj = JSON.parse(songs_json)

	songs_obj.each do |song_obj|
		song_record = Song.find_or_create_by(name: song_obj[0])
		tag_names = song_obj[1]
		tag_names.each do |tag_name|
			tag = Tag.find_or_create_by(name: tag_name)
			song_record.tags << tag
		end
	end
end

post '/listen' do
	begin
		user = User.find_by(name: params[:user_name])
		song_names = params[:song_names]
		song_names.each do |song_name|
			song = Song.find_by(name: song_name)
	    if user && song
	      user.listen!(song)
	    else
	      error 400, "Invalid relation between non-existant User or music record"
	    end
	  end
  rescue => e
    error 400, e.message.to_json
  end
end

post '/follow' do
	begin
		follower = User.find_or_create_by(name: params[:follower])
		followee = User.find_or_create_by(name: params[:followee])
    follower.follow!(followee)
  rescue => e
    error 400, e.message.to_json
  end
end

get '/recommendations/' do
	user = User.find_by(id: params[:id])
	result = get_recommended_songs_for_user(user)
	erb "<%= result %>", :locals => {:result => result}
end

private
	# The algorithm of getting the recommencations depends on the following:
	#
	# 1- How often the song's tag appeared in the user's history.
	# 2- Whether or not this song was listened to by any of the user's followees.
	# 3- Whether or not this song is new to the user.
	#
	# The algorithm gives each candidate for recommendations a weight and then uses
	# weighted randomness to generate a list of 5 recommendations per user. (The
	# higher the weight, the better change the song will be selected)
	def get_recommended_songs_for_user(user)

		# get distinct tags of user music history with how frequent each tag was played.
		weighted_tags = get_tags_of_user_history(user)

		# get all songs with these tags id's
		tag_ids = weighted_tags.keys
		candidates_by_tags = Song.any_in(tag_ids: tag_ids).entries

		weighted_candidates = {}
		candidates_by_tags.each do |candidate|
			sum = candidate.tags.inject(0) do |sum, tag|
				# get corresponding weighted tag
				weighted_tag = weighted_tags.select{|key, weight| key == tag.id }
				sum += weighted_tag[tag.id] || 0
				sum
			end

			weighted_candidates[candidate.id] = sum
		end

		candidates_by_following = get_followee_candidates(user)
		candidates_by_following.each do |candidate|
			weighted_candidates[candidate.id] ||= 0
			weighted_candidates[candidate.id] += FOLLOWEE_SONG_VALUE
		end

		# give more weight to new songs
		weighted_candidates.each do |candidate|
			candidate[1] *= NEW_SONGS_COEFFICIENT if !user.song_ids.include?(candidate[0])
		end

		result = get_random_recommendations(weighted_candidates)
	end

	# gets candidates by looking into followee's song history
	def get_followee_candidates(user)
		candidates = []

		user.following.each do |followee|
			candidates = candidates + followee.songs
		end
		candidates
	end

	def get_tags_of_user_history(user)
		weighted_tags = {}
		user.songs.each do |song|
			song.tag_ids.each do |tag_id|
				weighted_tags[tag_id] ||= 0
				weighted_tags[tag_id] += TAG_VALUE
			end
		end
		weighted_tags
	end

	# Returns 5 weighted random recommendations given a list of candidates
	def get_random_recommendations(weighted_candidates)
		total_weight = weighted_candidates.inject(0) { |sum, candidate| sum + candidate[1] }
		
		# initialize recommendations hash array
		recommendations = {}
		recommendations["list"] = []

		(1..RECOMMENDAITONS_MAX).each do |iteration|
			r = Random.rand(0 .. total_weight)
			weighted_candidates.each do |candidate|
				next if recommendations['list'].include?(candidate[0])
				r -= candidate[1]

				if r <= 0
					recommendations["list"] << candidate[0]

					# subtract the newly added song's weight from the total weight of
					# the remaining songs
					total_weight -= candidate[1]
					break
				end
			end
		end

		# for testing
		recommendations["list"].each do |r|
			ap Song.find_by(_id: r).name
		end

		recommendations
	end
