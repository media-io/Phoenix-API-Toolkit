# Phoenix API Toolkit

![Actions Status](https://github.com/weareyipyip/Phoenix-API-Toolkit/workflows/CI%20/%20Automated%20testing/badge.svg)

The Phoenix API Toolkit consists of several modules designed to aid in the development of (mainly REST) API's with Elixir/Phoenix. While Phoenix and the ecosystem on which it depends (`Ecto` and `Plug`) provide much out of the box, you will find yourself writing some repetitive code when creating a flexible API. This library aims to reduce that repetition. 

The functionality in this library mainly grew out of our experience developing REST (or so-called-REST) API's and the possibly differing requirements of GraphQL API's were not taken into account. That being said, the functionality offered is usually quite generic, and can be useful in developing such an API as well. 

## Dynamic Ecto query filtering and generic queries 

Imagine an index endpoint that supports filtering, searching, ordering and pagination, so that this HTTP call is possible, for example:

`GET /api/users?username=pete*&order_by=asc:last_name&birthday_before=2010-05-20&limit=20`

To support filtering based on Ecto model fields, you would soon find yourself writing a lot of queries like these:

```elixir 
defmodule User do 
  def by_first_name(query, first_name) do 
    from [user: user] in query, where: user.first_name == ^first_name 
  end 

  def by_birthday_before(query, date) do 
    from [user: user] in query, where: user.birthday < ^date 
  end 
end 
``` 

When taking into account that many fields like date fields and number fields logically benefit from smaller-than / greater-than filtering in addition to literal matching, the number of subqueries needed in the Ecto models and the complexity of the functions in the model context needed to support such functionality accross the API explodes.

### Dynamic filters

It is possible to create a list-function in the context of the model. This function can become quite complicated / verbose as well. For example:

```elixir
defmodule UserContext do
  def list(filters \\ %{}) do
    base_query = from(user in "users" as: :user)

    Enum.reduce(filters, base_query, fn filter, query -> 
      {:first_name, value} -> where([user: user], user.first_name == ^value)
      {:birthday_before, value} -> where([user: user], user.birthday < ^value)
      {:order_by, value} -> order_by(query, [user: user], ^value)
      _ -> query
    end)    
  end
end
```

Etc etc. For a model with 10 fields and order by / smaller than / greater than variants for each, a lot of code is required to support it all, with great potential for typing errors. Testing it all will grow tedious quickly.

To solve this issue, standard filters can be applied using the `PhoenixApiToolkit.Ecto.DynamicFilters.standard_filters/4` macro, which can be conveniently combined with `PhoenixApiToolkit.Ecto.DynamicFilters.apply_filters/3` to get a nice query pipe. It supports various filtering styles: among them are literal matches, set membership, smaller/greater than comparisons, ordering and pagination. Standard filters can be combined with non-standard custom filters. The supported filters must be configured at compile time.

```elixir
@filter_definitions [
  literals: [:first_name],  
  smaller_than: [birthday_before: :birthday]
]

# a custom filter function
def by_group_name(query, group_name) do
  from(
    [user: user] in query,
    join: group in assoc(user, :group),
    as: :group,
    where: group.name == ^group_name
  )
end

@doc """
My awesome list function. You can filter it, you know! And we guarantee the docs are up-to-date!

#{generate_filter_docs(@filter_definitions, literals: [:group_name])}
"""
def list_with_standard_filters(filters \\ %{}) do
  from(user in "users", as: :user)
  |> apply_filters(filters, fn
    # Add custom filters first and fallback to standard filters
    {:group_name, value}, query -> by_group_name(query, value)
    filter, query -> standard_filters(query, filter, :user, @filter_definitions)
  end)
end
```

It is difficult to keep such a flexible function and its documentation in sync. To aid in doing so, documentation for standard filters can be autogenerated using `PhoenixApiToolkit.Ecto.DynamicFilters.generate_filter_docs/2`. In the example above, the literal filter `:group_name` is passed as an extra. The `generate_filter_docs/2` call above will generate documentation for the function. See `PhoenixApiToolkit.Ecto.DynamicFilters` for more info.

## HTTP request validation

By validating HTTP requests, unexpected errors can be prevented and useful feedback returned to the client. Additionally, invalid or dangerous input can be caught early. Note that the `PhoenixApiToolkit.Ecto.DynamicFilters.standard_filters/4` macro relies on atom keys in the filters. To prevent atom-creation leaks, input for such filters must be validated as well. Validating HTTP requests can be done simply by using `Ecto.Changeset`s. A generic request validator to use as a basis has been created in `PhoenixApiToolkit.GenericRequestValidator`. A detailed example can be seen in its hex doc.

## Security plugs 

Security is always a complex topic of seemingly infinite depth. In order to help developers to maintain proper standards and adapt good practices, the Open Web Application Security Project or OWASP provides guidelines and detailed advice on several aspects of security, from recommended token timeouts to HTTP request/response headers to database design best practices. 

There are guidelines for [REST API security](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html), and the security plugs in this library implement some of these guidelines. 

- The Oauth2 plug `PhoenixApiToolkit.Security.Oauth2Plug` can verify Oauth2 access / ID tokens, so that your API can use an external Oauth2/OpenID Connect provider for authentication / authorization (like Auth0 or Keycloak). Requires `:jose` dependency in your mix.exs file.
- The HMAC plug `PhoenixApiToolkit.Security.HmacPlug` can verify HMAC-signed requests, ensuring that the request body was sent by a known entity and was not tampered with on-route. Useful for (private) API-to-API communication. 
- The function plugs in `PhoenixApiToolkit.Security.Plugs` serve several purposes, like checking request headers, verifying additional JWT claims and setting default response headers. 

## Test helpers

The API toolkit provides several test helpers in `PhoenixApiToolkit.TestHelpers`. These are mainly meant to aid in writing integration tests in Phoenix, especially for endpoints secured using the Oauth2 plug or the HMAC plug. The test helpers can generate valid tokens for requests during testing. Some additional utility functions are included as well.

## Installation 

The package can be installed by adding `phoenix_api_toolkit` to your list of dependencies in `mix.exs`:

```elixir 
def deps do 
  [ 
      {:phoenix_api_toolkit, "~> 0.14.0"} 
  ] 
end 
``` 

## Documentation 
Documentation is available on [HexDocs](https://hexdocs.pm/phoenix_api_toolkit/)