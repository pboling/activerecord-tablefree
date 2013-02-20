ActiveRecord Tableless
======================

A single implementation of the ActiveRecord Tableless pattern for any
Rails project or other Ruby project that uses ActiveRecord.

Installation
------------

ActiveRecord Tableless is distributed as a gem, which is how it should
be used in your app.

Include the gem in your Gemfile:

    gem "activerecord-tableless", "~> 1.0"


Supported Versions
------------------

Supported version are ActiveRecord version **2.3.x**, **3.0.x** series
and **3.2.x** series

You may be able to make it work with 3.1.X, but you should expect to
put some time in it.

Usage
-----

Define a model like this:

    class ContactMessage < ActiveRecord::Base
      has_no_table
      column :name, :string
      column :email, :string
      validates_presence_of :name, :email
    end

You can now use the model in a view like this:

    <%= form_for :message, @message do |f| %>
      Your name: <%= f.text_field :name %>
      Your email: <%= f.text_field :email %>
    <% end %>

And in the controller:

    def message
      @message = ContactMessage.new
      if request.post?
        @message.attributes = params[:message]
        if @message.valid?
          # Process the message...
        end
      end
    end

For Rails 2.3.x series you need to add this line in the top of your model file.

    require 'activerecord-tableless'


Development
-----------

To start develop, please download the source code

    git clone git://github.com/softace/activerecord-tableless.git

When downloaded, you can start issuing the commands like

    bundle install
    bundle exec rake appraisal:gemfiles
    bundle exec rake appraisal:install
    bundle exec rake appraisal

Or you can see what other options are there:

    bundle exec rake -T


History
-------

Well, take a look at the git log :-)


Copyright
---------

Copyright (c) Jarl Friis. See LICENSE.txt for
further details.
