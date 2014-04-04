require 'spec_helper'

describe "recommendation script" do

  it "should return 5 recommendations for user a" do

  	# Feed user followees
  	follows_json = File.read('follows.json')
  	follows_obj = JSON.parse(follows_json)

		follows_obj['operations'].each do |follow_obj|
	     post '/follow', {
	      :follower => follow_obj[0],
	      :followee => follow_obj[1]
	    }
	  end

	  # Feed user songs
	  listen_json = File.read('listen.json')
  	listen_obj = JSON.parse(listen_json)

		listen_obj['userIds'].each do |listen_obj|
	     post '/listen', {
	      :user_name => listen_obj[0],
	      :song_names => listen_obj[1]
	    }
	  end

	  get '/recommendations/', {
	  	:id => User.find_by(name: "a").id
	  }

	  ap last_response.body
  end
end