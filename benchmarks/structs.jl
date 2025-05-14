const root_json = """
{
  "store": {
    "book": [
      {
        "id": 1,
        "category": "reference",
        "author": "Nigel Rees",
        "title": "Sayings of the Century",
        "price": 8.95,
        "tags": ["classic", "quotes"],
        "available": true,
        "metadata": null
      },
      {
        "id": 2,
        "category": "fiction",
        "author": "Herman Melville",
        "title": "Moby Dick",
        "isbn": "0-553-21311-3",
        "price": 8.99,
        "tags": ["whale", "sea", "epic"],
        "available": false,
        "metadata": {
          "pages": 635,
          "language": "en",
          "awards": []
        }
      },
      {
        "id": 3,
        "category": "fiction",
        "author": "J.R.R. Tolkien",
        "title": "The Lord of the Rings",
        "isbn": "0-395-19395-8",
        "price": 22.99,
        "tags": ["fantasy", "adventure"],
        "available": true,
        "metadata": {
          "pages": 1216,
          "language": "en",
          "awards": ["Prometheus Hall of Fame"]
        }
      }
    ],
    "bicycle": {
      "id": "bike123",
      "color": "red",
      "price": 19.95,
      "features": {
        "gears": 21,
        "electric": false,
        "dimensions": {
          "length_cm": 180,
          "height_cm": 110,
          "weight_kg": 14.5
        }
      }
    },
    "warehouse": [
      {
        "location": "North",
        "inventory": {
          "books": 1500,
          "bicycles": 34,
          "lastRestock": "2024-11-15T10:30:00Z",
          "active": true
        }
      },
      {
        "location": "South",
        "inventory": {
          "books": 980,
          "bicycles": 12,
          "lastRestock": null,
          "active": false
        }
      }
    ]
  },
  "expensive": 10,
  "config": {
    "version": "1.2.3",
    "featuresEnabled": ["wishlist", "reviews", "recommendations"],
    "limits": {
      "maxBooksPerUser": 20,
      "maxSessions": 5,
      "discounts": {
        "student": 0.15,
        "senior": 0.2
      }
    },
    "debug": false
  },
  "users": [
    {
      "id": 1001,
      "name": "Alice",
      "email": "alice@example.com",
      "lastLogin": "2025-03-27T16:45:00Z",
      "preferences": {
        "language": "en",
        "currency": "USD",
        "newsletter": true
      }
    },
    {
      "id": 1002,
      "name": "Bob",
      "email": null,
      "lastLogin": null,
      "preferences": {
        "language": "fr",
        "currency": "EUR",
        "newsletter": false
      }
    }
  ]
}
"""
struct Preferences
    language::String
    currency::String
    newsletter::Bool
end

struct User
    id::Int
    name::String
    email::Union{String, Nothing}
    lastLogin::Union{String, Nothing}
    preferences::Preferences
end

struct Discounts
    student::Float64
    senior::Float64
end

struct Limits
    maxBooksPerUser::Int
    maxSessions::Int
    discounts::Discounts
end

struct Config
    version::String
    featuresEnabled::Vector{String}
    limits::Limits
    debug::Bool
end

struct Inventory
    books::Int
    bicycles::Int
    lastRestock::Union{String, Nothing}
    active::Bool
end

struct Warehouse
    location::String
    inventory::Inventory
end

struct BikeDimensions
    length_cm::Int
    height_cm::Int
    weight_kg::Float64
end

struct BikeFeatures
    gears::Int
    electric::Bool
    dimensions::BikeDimensions
end

struct Bicycle
    id::String
    color::String
    price::Float64
    features::BikeFeatures
end

struct BookMetadata
    pages::Int
    language::String
    awards::Vector{String}
end

struct Book
    id::Int
    category::String
    author::String
    title::String
    price::Float64
    tags::Vector{String}
    available::Bool
    metadata::Union{BookMetadata, Nothing}
end

struct Store
    book::Vector{Book}
    bicycle::Bicycle
    warehouse::Vector{Warehouse}
end

struct Root
    store::Store
    expensive::Int
    config::Config
    users::Vector{User}
end
