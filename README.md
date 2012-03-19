Has Metadata Column -- Keep your tables narrow
===================

|             |                                 |
|:------------|:--------------------------------|
| **Author**  | Tim Morgan                      |
| **Version** | 1.0.1 (Mar 19, 2012)            |
| **License** | Released under the MIT License. |

About
-----

So you're wondering why it is you need to make, test, schedule, and deploy a
whole nother migration just to add one more freeform "Favorite Music"-type
column to your users model?  Wish there were an easier way?

There is! Combine all of those "about me," "favorite music," etc. type fields
into _one_ JSON-serialized `TEXT` column, and now every model can have
schemaless, migration-free data.

If you're interested in moving your metadata out to another table (or database)
entirely, consider using
[HasMetadata](https://github.com/riscfuture/has_metadata).

This gem does use some "metaprogramming magic" to make the metadata fields
appear like first-class fields, for purposes of validation and easy access. If
this is unsettling to you, I recommend using my gem
[JsonSerialize](https://github.com/riscfuture/json_serialize) instead, as it
does not get its little fingers all up in ActiveRecord's business.

(Why yes, I _do_ have a gem for a every use case!)

h2. Installation

**Important Note:** This gem is only compatible with Ruby 1.9 and Rails 3.0.

Merely add the gem to your Rails project's `Gemfile`:

```` ruby
gem 'has_metadata_column'
````

Usage
-----

The first thing to think about is what columns to keep. You will need to keep
any indexed columns, or any columns you perform lookups or other SQL queries
with. You should also keep any frequently accessed columns, especially if they
are small (integers or booleans). Good candidates for the metadata column are
the `TEXT`- and `VARCHAR`-type columns that you only need to render a page or
two in your app.

You'll need to add a `TEXT` column to your model to store the metadata. You can
call it what you want; `metadata` is assumed by default.

```` ruby
t.text :metadata
````

Next, include the `HasMetadataColumn` module in your model, and call the
`has_metadata_column` method to define the schema of your metadata. You can get
more information in the {HasMetadataColumn::ClassMethods#has_metadata_column}
documentation, but for starters, here's a basic example:

```` ruby
class User < ActiveRecord::Base
  include HasMetadataColumn
  has_metadata(
    :my_metadata_column,
    about_me:  { type: String, length: { maximum: 512 } },
    birthdate: { type: Date, presence: true },
    zipcode:   { type: Number, numericality: { greater_than: 9999, less_than: 10_000 } }
  )
end
````

As you can see, you pass field names mapped to a hash. The hash describes the
validation that will be performed, and is in the same format as a call to
`validates`. In addition to the `EachValidator` keys shown above, you can also
pass a `type` key, to constrain the Ruby type that can be assigned to the field.
You can only assign types that can be JSON-serialized: strings, numbers, arrays,
hashes, dates/times, booleans, and `nil`.

Each of these fields (in this case, `about_me`, `birthdate`, and `zipcode`) can
be accessed and set as first_level methods on an instance of your model:

```` ruby
user.about_me #=> "I was born in 1982 in Aberdeen. My father was a carpenter from..."
````

... and thus, used as part of `form_for` fields:

```` ruby
form_for user do |f|
  f.text_area :about_me, rows: 5, cols: 80
end
````

... and validations.

The only thing you _can't_ do is use these fields in a query, obviously. You
can't do something like `User.where(zipcode: 90210)`, because that column
doesn't exist on the `users` table.

... Unless you use PostgreSQL 9.2, and define your metadata column as type
`json`. Support for _that_ is coming...
