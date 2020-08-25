defmodule PhoenixApiToolkit.Ecto.DynamicFilters do
  @moduledoc """
  Dynamic filtering of Ecto queries is useful for creating list/index functions,
  and ultimately list/index endpoints, that accept a map of filters to apply to the query.
  Such a map can be based on HTTP query parameters, naturally.

  Several filtering types are so common that they have been implemented using standard filter
  macro's. This way, you only have to define which fields are filterable in what way.

  Documentation for such filters can be autogenerated using `generate_filter_docs/2`.

  ## Example without standard filters

      import Ecto.Query
      require Ecto.Query

      def list_without_standard_filters(filters \\\\ %{}) do
        from(user in "users", as: :user)
        |> apply_filters(filters, fn
          {:order_by, {field, direction}}, query ->
            order_by(query, [user: user], [{^direction, field(user, ^field)}])

          {filter, value}, query when filter in [:id, :name, :residence, :address] ->
            where(query, [user: user], field(user, ^filter) == ^value)

          _, query ->
            query
        end)
      end

      # filtering is optional
      iex> list_without_standard_filters()
      #Ecto.Query<from u0 in "users", as: :user>

      # multiple equal_to matches can be combined
      iex> list_without_standard_filters(%{residence: "New York", address: "Main Street"})
      #Ecto.Query<from u0 in "users", as: :user, where: u0.address == ^"Main Street", where: u0.residence == ^"New York">

      # equal_to matches and sorting can be combined
      iex> list_without_standard_filters(%{residence: "New York", order_by: {:name, :desc}})
      #Ecto.Query<from u0 in "users", as: :user, where: u0.residence == ^"New York", order_by: [desc: u0.name]>

      # other fields are ignored / passed through
      iex> list_without_standard_filters(%{number_of_arms: 3})
      #Ecto.Query<from u0 in "users", as: :user>

  ## Example with standard filters and autogenerated docs

  Standard filters can be applied using the `standard_filters/4` macro. It supports various filtering styles:
  equal_to matches, set membership, smaller/greater than comparisons, ordering and pagination. These filters must
  be configured at compile time. Standard filters can be combined with non-standard custom filters.
  Documentation can be autogenerated.


      @filter_definitions [
        atom_keys: true,
        string_keys: true,
        limit: true,
        offset: true,
        order_by: true,
        equal_to: [:id, :username, :address, :balance, role_name: {:role, :name}],
        equal_to_any: [:address],
        string_starts_with: [username_prefix: {:user, :username}],
        string_contains: [username_search: :username],
        list_contains: [:roles],
        list_contains_any: [:roles],
        list_contains_all: [all_roles: :roles],
        smaller_than: [
          inserted_before: :inserted_at,
          balance_lt: :balance,
          role_inserted_before: {:role, :inserted_at}
        ],
        greater_than_or_equal_to: [
          inserted_at_or_after: :inserted_at,
          balance_gte: :balance
        ]
      ]

      @doc \"\"\"
      Custom filter function
      \"\"\"
      def by_group_name(query, group_name) do
        where(query, [user: user], user.group_name == ^group_name)
      end

      @doc \"\"\"
      Function to resolve named bindings by dynamically joining them into the query.
      \"\"\"
      def resolve_binding(query, named_binding) do
        if has_named_binding?(query, named_binding) do
          query
        else
          case named_binding do
            :role -> join(query, :left, [user: user], role in "roles", as: :role)
            _ -> query
          end
        end
      end

      @doc \"\"\"
      My awesome list function. You can filter it, you know! And we guarantee the docs are up-to-date!

      \#{generate_filter_docs(@filter_definitions, equal_to: [:group_name])}
      \"\"\"
      def list_with_standard_filters(filters \\\\ %{}) do
        from(user in "users", as: :user)
        |> apply_filters(filters, fn
          # Add custom filters first and fallback to standard filters
          {:group_name, value}, query ->
            by_group_name(query, value)

          filter, query ->
            standard_filters(query, filter, :user, @filter_definitions, &resolve_binding/2)
        end)
      end

      # filtering is optional
      iex> list_with_standard_filters()
      #Ecto.Query<from u0 in "users", as: :user>

      # let's do some filtering
      iex> list_with_standard_filters(%{username: "Peter", balance_lt: 50.00, address: "sesame street"})
      #Ecto.Query<from u0 in "users", as: :user, where: u0.address == ^"sesame street", where: u0.balance < ^50.0, where: u0.username == ^"Peter">

      # associations can be dynamically joined into the query, only when necessary
      iex> list_with_standard_filters(%{role_name: "admin"})
      #Ecto.Query<from u0 in "users", as: :user, left_join: r1 in "roles", as: :role, on: true, where: r1.name == ^"admin">

      # limit, offset, and order_by are supported
      iex> list_with_standard_filters(%{"limit" => 10, offset: 1, order_by: [desc: :address]})
      #Ecto.Query<from u0 in "users", as: :user, order_by: [desc: u0.address], limit: ^10, offset: ^1>

      # order_by can use association fields as well, which are dynamically joined in that case
      iex> list_with_standard_filters(%{order_by: [asc: {:role, :name}]})
      #Ecto.Query<from u0 in "users", as: :user, left_join: r1 in "roles", as: :role, on: true, order_by: [asc: r1.name]>

      # order_by can use equal_to aliases as well, without breaking dynamic joining
      iex> list_with_standard_filters(%{order_by: [asc: :role_name]})
      #Ecto.Query<from u0 in "users", as: :user, left_join: r1 in "roles", as: :role, on: true, order_by: [asc: r1.name]>

      # complex custom filters can be combined with the standard filters
      iex> list_with_standard_filters(%{group_name: "admins", balance_gte: 50.00})
      #Ecto.Query<from u0 in "users", as: :user, where: u0.balance >= ^50.0, where: u0.group_name == ^"admins">

      # unsupported filters raise, but nonexistent order_by fields do not (although Ecto will raise, naturally)
      iex> list_with_standard_filters(%{number_of_arms: 3})
      ** (CaseClauseError) no case clause matching: {:number_of_arms, 3}
      iex> list_with_standard_filters(%{order_by: [:number_of_arms]})
      #Ecto.Query<from u0 in "users", as: :user, order_by: [asc: u0.number_of_arms]>

      # filtering on lists of values, string prefixes and string-contains filters
      iex> list_with_standard_filters(%{address: ["sesame street"], username_prefix: "foo", username_search: "bar"})
      #Ecto.Query<from u0 in "users", as: :user, where: u0.address in ^["sesame street"], where: ilike(u0.username, ^"foo%"), where: ilike(u0.username, ^"%bar%")>

      # filtering on array-type fields
      iex> list_with_standard_filters(%{roles: "admin"})
      #Ecto.Query<from u0 in "users", as: :user, where: ^"admin" in u0.roles>
      iex> list_with_standard_filters(%{roles: ["admin", "superadmin"], all_roles: ["creator", "user"]})
      #Ecto.Query<from u0 in "users", as: :user, where: fragment("? @> ?", u0.roles, ^["creator", "user"]), where: fragment("? && ?", u0.roles, ^["admin", "superadmin"])>

      # you can order by multiple fields and specify bindings
      iex> list_with_standard_filters(%{"balance" => 12, "order_by" => [asc: {:user, :username}, desc: :role]})
      #Ecto.Query<from u0 in "users", as: :user, where: u0.balance == ^12, order_by: [asc: u0.username], order_by: [desc: u0.role]>

  Note that the aim is not to emulate GraphQL in a REST API. It is not possible for the API client to specify which fields the API should return or how deep the nesting should be: it is still necessary to develop different REST resources for differently-shaped responses (for example, `/api/users` or `/api/users_with_groups` etc). In a REST API, simple filtering and sorting functionality can be supported, however, without going the full GraphQL route. We will not discuss the pro's and cons of GraphQL versus REST here, but we maintain that GraphQL is not a drop-in replacement for REST API's in every situation and there is still a place for (flexible) REST API's, for example when caching on anything other than the client itself is desired or when development simplicity trumps complete flexibility and the number of different clients is limited.

  ## Generating documentation

  The call to `generate_filter_docs/2` for the filter definitions as defined above will generate the following (rendered) docs:

  > ## Filter key types
  >
  > Filter keys may be both atoms and strings, e.g. %{username: "Dave123", "first_name" => "Dave"}
  >
  > ## Equal-to filters
  >
  > The field's value must be equal to the filter value.
  > The equivalent Ecto code is
  > ```
  > where(query, [binding: bd], bd.field == ^filter_value)
  > ```
  > Additionally, aliases defined in equal-to filters, like `[role_name: {:role, :name}]` can be used in `order_by` as well.
  > The following filter names are supported:
  > * `address`
  > * `balance`
  > * `group_name`
  > * `id`
  > * `role_name` (actual field is `role.name)`
  > * `username`
  >
  > ## Equal-to-any filters
  >
  > The field's value must be equal to any of the filter values.
  > The equivalent Ecto code is
  > ```
  > where(query, [binding: bd], bd.field in ^filter_value)
  > ```
  > The following filter names are supported:
  > * `address`
  >
  > ## Smaller-than filters
  >
  > The field's value must be smaller than the filter's value.
  > The equivalent Ecto code is
  > ```
  > where(query, [binding: bd], bd.field < ^filter_value)
  > ```
  > The following filter names are supported:
  >
  > Filter name | Must be smaller than
  > --- | ---
  > `balance_lt` | `balance`
  > `inserted_before` | `inserted_at`
  > `role_inserted_before` | `role.inserted_at`
  >
  > ## Greater-than-or-equal-to filters
  >
  > The field's value must be greater than or equal to the filter's value.
  > The equivalent Ecto code is
  > ```
  > where(query, [binding: bd], bd.field >= ^filter_value)
  > ```
  > The following filter names are supported:
  >
  > Filter name | Must be greater than or equal to
  > --- | ---
  > `balance_gte` | `balance`
  > `inserted_at_or_after` | `inserted_at`
  >
  > ## String-starts-with filters
  >
  > The string-type field's value must start with the filter's value.
  > The equivalent Ecto code is
  > ```
  > where(query, [binding: bd], ilike(bd.field, ^(val <> "%")))
  > ```
  > The following filter names are supported:
  > * `username_prefix` (actual field is `user.username)`
  >
  > ## String-contains filters
  >
  > The string-type field's value must contain the filter's value.
  > The equivalent Ecto code is
  > ```
  > where(query, [binding: bd], ilike(bd.field, ^("%" <> val <> "%")))
  > ```
  > The following filter names are supported:
  > * `username_search` (actual field is `username)`
  >
  > ## List-contains filters
  >
  > The array-type field's value must contain the filter's value (set membership).
  > The equivalent Ecto code is
  > ```
  > where(query, [binding: bd], ^filter_value in bd.field)
  > ```
  > The following filter names are supported:
  > * `roles`
  >
  > ## List-contains-any filters
  >
  > The array-type field's value must contain any of the filter's values (set intersection).
  > The equivalent Ecto code is
  > ```
  > where(query, [binding: bd], fragment("? && ?", bd.field, ^val))
  > ```
  > The following filter names are supported:
  > * `roles`
  >
  > ## List-contains-all filters
  >
  > The array-type field's value must contain all of the filter's values (subset).
  > The equivalent Ecto code is
  > ```
  > where(query, [binding: bd], fragment("? @> ?", bd.field, ^val))
  > ```
  > The following filter names are supported:
  > * `all_roles` (actual field is `roles)`
  >
  > ## Order-by sorting
  >
  > Order-by filters do not actually filter the result set, but sort it according to the filter's value(s).
  >
  > Order-by filters take a list argument, that can consist of the following elements:
  > - `field` will sort on the specified field of the default binding in ascending order
  > - `{:direction, :field}` will sort on the specified field of the default binding in the specified direction
  > - `{:direction, {:binding, :field}}` will sort on the specified field of the specified binding in the specified direction.
  >
  > Note that the value of `order_by` filters must consist of atoms, even with `string_keys` enabled.
  >
  > All fields present in the query on any named binding are supported, including field name aliases specified in the filter definitions under equal_to.
  > For example, in case of filter definitions `[equal_to: [role_name: {:role, :name}]]`, the following will work: `%{order_by: [desc: :role_name]}`.
  >
  > The supported directions can be found in the docs of `Ecto.Query.order_by/3`.
  >
  > ## Limit filter
  >
  > The `limit` filter sets a maximum for the number of rows in the result set and may be used for pagination.
  >
  > ## Offset filter
  >
  > The `offset` filter skips a number of rows in the result set and may be used for pagination.
  >
  >
  """
  alias Ecto.Query
  import Ecto.Query
  require Ecto.Query

  @typedoc "Format of a filter that can be applied to a query to narrow it down"
  @type filter :: {atom() | String.t(), any()}

  @doc """
  Applies `filters` to `query` by reducing `filters` using `filter_reductor`.
  Combine with the custom queries from `Ecto.Query` to write complex
  filterables. Several standard filters have been implemented in
  `standard_filters/4`.

  See the module docs `#{__MODULE__}` for details and examples.
  """
  @spec apply_filters(Query.t(), map(), (Query.t(), filter -> Query.t())) :: Query.t()
  def apply_filters(query, filters, filter_reductor) do
    Enum.reduce(filters, query, filter_reductor)
  end

  @typedoc """
  Definition used to generate a filter for `standard_filters/4`.

  May take the following forms:
  - `atom` filter name and name of field of default binding
  - `{filter_name, actual_field}` if the filter name is different from the name of the field of the default binding
  - `{filter_name, {binding, actual_field}}` if the field is a field of another named binding
  """
  @type filter_definition :: atom | {atom, atom} | {atom, {atom, atom}}

  @typedoc """
  Filter definitions supported by `standard_filters/4`.
  A keyword list of filter types and the filter definitions for which they should be generated.
  """
  @type filter_definitions :: [
          atom_keys: boolean(),
          string_keys: boolean(),
          limit: boolean(),
          offset: boolean(),
          order_by: boolean(),
          equal_to: [filter_definition()],
          equal_to_any: [filter_definition()],
          smaller_than: [filter_definition()],
          greater_than_or_equal_to: [filter_definition()],
          string_starts_with: [filter_definition()],
          string_contains: [filter_definition()],
          list_contains: [filter_definition()],
          list_contains_any: [filter_definition()],
          list_contains_all: [filter_definition()]
        ]

  @typedoc """
  Extra filters supported by a function, for which documentation should be generated by `generate_filter_docs/2`.
  A keyword list of filter types and the fields for which documentation should be generated.
  """
  @type extra_filter_definitions :: [
          equal_to: [filter_definition()],
          equal_to_any: [filter_definition()],
          smaller_than: keyword(filter_definition()),
          greater_than_or_equal_to: keyword(filter_definition()),
          string_starts_with: [filter_definition()],
          string_contains: [filter_definition()],
          list_contains: [filter_definition()],
          list_contains_any: [filter_definition()],
          list_contains_all: [filter_definition()]
        ]

  @doc """
  Applies standard filters to the query. Standard
  filters include filters for equal_to matches, set membership, smaller/greater than comparisons,
  ordering and pagination.

  See the module docs `#{__MODULE__}` for details and examples.

  Mandatory parameters:
  - `query`: the Ecto query that is narrowed down
  - `filter`: the current filter that is being applied to `query`
  - `default_binding`: the named binding of the Ecto model that generic queries are applied to, unless specified otherwise
  - `filter_definitions`: keyword list of filter types and the filter definitions for which they should be generated

  Optional parameters:
  - resolve_binding: a function that can be passed in to dynamically join the query to resolve named bindings requested in filters

  The options supported by the `filter_definitions` parameter are:
  - `atom_keys`: supports filter keys as atoms, e.g. `%{username: "Dave"}`
  - `string_keys`: supports filter keys as strings, e.g. `%{"username" => "Dave"}`. Note that order_by VALUES must always be atoms: `%{"order_by" => :username}` will work but `%{order_by: "username"}` will not.
  - `limit`: enables limit filter
  - `offset`: enables offset filter
  - `order_by`: enables order_by filter
  - `equal_to`: field must be equal to filter. Aliases like `[role_name: {:role, :name}]` can be used in `order_by` as well.
  - `equal_to_any`: field must be equal to any value of filter, e.g. `user.id in [1, 2, 3]`. Filter names can be the same as `equal_to` filters.
  - `smaller_than`: field must be smaller than filter value, e.g. `user.score < value`
  - `greater_than_or_equal_to`: field must be greater than or equal to filter value, e.g. `user.score >= value`
  - `string_starts_with`: string field must start with case-insensitive string prefix, e.g. `user.name` starts with "dav"
  - `string_contains`: string field must contain case-insensitive string, e.g. `user.name` contains "av"
  - `list_contains`: array field must contain filter value, e.g. `"admin" in user.roles` (equivalent to set membership)
  - `list_contains_any`: array field must contain any filter value, e.g. `user.roles` contains any of ["admin", "creator"] (equivalent to set intersection). Filter names can be the same as `list_contains` filters.
  - `list_contains_all`: array field must contain all filter values, e.g. `user.roles` contains all of ["admin", "creator"] (equivalent to subset). Filter names can be the same as `list_contains` filters.
  """
  @spec standard_filters(
          Query.t(),
          filter,
          atom,
          filter_definitions,
          (Query.t(), atom() -> Query.t())
        ) :: any
  defmacro standard_filters(
             query,
             filter,
             default_binding,
             filter_definitions,
             resolve_binding
           )

  defmacro standard_filters(query, filter, def_bnd, filter_definitions, res_binding) do
    # Call Macro.expand/2 in case filter_definitions is a module attribute
    definitions = filter_definitions |> Macro.expand(__CALLER__)

    # create clauses for the eventual case statement (as raw AST!)
    clauses =
      []
      |> maybe_support_limit(definitions)
      |> maybe_support_offset(definitions)
      |> maybe_support_order_by(definitions, def_bnd, res_binding)
      # filters for equal-to-any-of-the-filters-values matches
      |> add_clause_for_each(definitions[:equal_to_any], def_bnd, fn {filt, bnd, fld}, clauses ->
        clauses
        |> add_clause(
          quote do
            {flt, val} when flt in unquote(create_keylist(definitions, filt)) and is_list(val)
          end,
          quote do
            query
            |> unquote(res_binding).(unquote(bnd))
            |> where([{^unquote(bnd), bd}], field(bd, unquote(fld)) in ^val)
          end
        )
      end)
      # filters for equality matches
      |> add_clause_for_each(definitions[:equal_to], def_bnd, fn {filt, bnd, fld}, clauses ->
        clauses
        |> add_clause(
          quote do
            {flt, val} when flt in unquote(create_keylist(definitions, filt))
          end,
          quote do
            query
            |> unquote(res_binding).(unquote(bnd))
            |> where([{^unquote(bnd), bd}], field(bd, unquote(fld)) == ^val)
          end
        )
      end)
      # filters for prefix searches using ilike
      |> add_clause_for_each(definitions[:string_starts_with], def_bnd, fn {filt, bnd, fld},
                                                                           clauses ->
        clauses
        |> add_clause(
          quote do
            {flt, val} when flt in unquote(create_keylist(definitions, filt))
          end,
          quote do
            query
            |> unquote(res_binding).(unquote(bnd))
            |> where([{^unquote(bnd), bd}], ilike(field(bd, unquote(fld)), ^(val <> "%")))
          end
        )
      end)
      # filters for searches using ilike
      |> add_clause_for_each(definitions[:string_contains], def_bnd, fn {filt, bnd, fld},
                                                                        clauses ->
        clauses
        |> add_clause(
          quote do
            {flt, val} when flt in unquote(create_keylist(definitions, filt))
          end,
          quote do
            query
            |> unquote(res_binding).(unquote(bnd))
            |> where([{^unquote(bnd), bd}], ilike(field(bd, unquote(fld)), ^("%" <> val <> "%")))
          end
        )
      end)
      # filters for set intersection matches
      |> add_clause_for_each(definitions[:list_contains_any], def_bnd, fn {filt, bnd, fld},
                                                                          clauses ->
        add_clause(
          clauses,
          quote do
            {flt, val} when flt in unquote(create_keylist(definitions, filt)) and is_list(val)
          end,
          quote do
            query
            |> unquote(res_binding).(unquote(bnd))
            |> where([{^unquote(bnd), bd}], fragment("? && ?", field(bd, unquote(fld)), ^val))
          end
        )
      end)
      # filters for subset-of matches
      |> add_clause_for_each(definitions[:list_contains_all], def_bnd, fn {filt, bnd, fld},
                                                                          clauses ->
        add_clause(
          clauses,
          quote do
            {flt, val} when flt in unquote(create_keylist(definitions, filt)) and is_list(val)
          end,
          quote do
            query
            |> unquote(res_binding).(unquote(bnd))
            |> where([{^unquote(bnd), bd}], fragment("? @> ?", field(bd, unquote(fld)), ^val))
          end
        )
      end)
      # filters for set membership matches
      |> add_clause_for_each(definitions[:list_contains], def_bnd, fn {filt, bnd, fld}, clauses ->
        add_clause(
          clauses,
          quote do
            {flt, val} when flt in unquote(create_keylist(definitions, filt))
          end,
          quote do
            query
            |> unquote(res_binding).(unquote(bnd))
            |> where([{^unquote(bnd), bd}], ^val in field(bd, unquote(fld)))
          end
        )
      end)
      # filters for smaller-than matches
      |> add_clause_for_each(definitions[:smaller_than], def_bnd, fn {filt, bnd, fld}, clauses ->
        add_clause(
          clauses,
          quote do
            {flt, val} when flt in unquote(create_keylist(definitions, filt))
          end,
          quote do
            query
            |> unquote(res_binding).(unquote(bnd))
            |> where([{^unquote(bnd), bd}], field(bd, unquote(fld)) < ^val)
          end
        )
      end)
      # filters for greater-than-or-equal-to matches
      |> add_clause_for_each(definitions[:greater_than_or_equal_to], def_bnd, fn {filt, bnd, fld},
                                                                                 clauses ->
        add_clause(
          clauses,
          quote do
            {flt, val} when flt in unquote(create_keylist(definitions, filt))
          end,
          quote do
            query
            |> unquote(res_binding).(unquote(bnd))
            |> where([{^unquote(bnd), bd}], field(bd, unquote(fld)) >= ^val)
          end
        )
      end)

    # create the case statement based on the clauses
    quote generated: true do
      query = unquote(query)
      def_bnd = unquote(def_bnd)

      case unquote(filter), do: unquote(clauses)
    end
  end

  @doc """
  Same as `standard_filters/5` but does not support dynamically resolving named bindings.
  """
  @spec standard_filters(
          Query.t(),
          filter,
          atom,
          filter_definitions
        ) :: any
  defmacro standard_filters(query, filter, default_binding, filter_definitions) do
    quote do
      standard_filters(
        unquote(query),
        unquote(filter),
        unquote(default_binding),
        unquote(filter_definitions),
        fn q, _ -> q end
      )
    end
  end

  @doc """
  Apply order_by filter, with `equal_to` aliases.

  ## Examples / doctests

      def list_order_by_only(filters \\\\ %{}) do
        from(user in "users", as: :user)
        |> apply_filters(Map.take(filters, [:order_by, "order_by"]), fn filter, query ->
          order_by_only(query, filter, :user, @filter_definitions, &resolve_binding/2)
        end)
      end

      iex> list_order_by_only(%{})
      #Ecto.Query<from u0 in "users", as: :user>

      iex> list_order_by_only(%{equal_to: [:first_name]})
      #Ecto.Query<from u0 in "users", as: :user>

      iex> list_order_by_only(%{"order_by" => [desc: :first_name, asc: :role_name]})
      #Ecto.Query<from u0 in "users", as: :user, left_join: r1 in "roles", as: :role, on: true, order_by: [desc: u0.first_name], order_by: [asc: r1.name]>
  """
  @spec order_by_only(
          Query.t(),
          filter(),
          atom(),
          filter_definitions(),
          (Query.t(), atom() -> Query.t())
        ) :: any()
  defmacro order_by_only(
             query,
             filter,
             default_binding,
             filter_definitions,
             resolve_binding
           ) do
    definitions = filter_definitions |> Macro.expand(__CALLER__)

    definitions = [
      order_by: true,
      atom_keys: definitions[:atom_keys],
      string_keys: definitions[:string_keys],
      equal_to: definitions[:equal_to]
    ]

    clauses =
      []
      |> maybe_support_order_by(definitions, default_binding, resolve_binding)

    quote generated: true do
      query = unquote(query)
      filter = unquote(filter)

      case filter, do: unquote(clauses)
    end
  end

  @doc """
  Same as `order_by_only/5` but does not support dynamically resolving named bindings.
  """
  @spec order_by_only(
          Query.t(),
          filter,
          atom,
          filter_definitions
        ) :: any
  defmacro order_by_only(
             query,
             filter,
             default_binding,
             filter_definitions
           ) do
    quote do
      order_by_only(
        unquote(query),
        unquote(filter),
        unquote(default_binding),
        unquote(filter_definitions),
        fn q, _ -> q end
      )
    end
  end

  @doc """
  Generate a markdown docstring from filter definitions, as passed to `standard_filters/4`,
  as defined by `t:filter_definitions/0`. By specifying `extras`, documentation can be generated
  for any custom filters supported by your function as well.

  See the module docs `#{__MODULE__}` for details and examples.
  """
  @spec generate_filter_docs(filter_definitions(), extra_filter_definitions()) :: binary
  def generate_filter_docs(filters, extras \\ []) do
    equal_to = get_filters(:equal_to, filters, extras)
    list_contains = get_filters(:list_contains, filters, extras)
    smaller_than = get_filters(:smaller_than, filters, extras)
    greater_than_or_equal_to = get_filters(:greater_than_or_equal_to, filters, extras)
    equal_to_any = get_filters(:equal_to_any, filters, extras)
    string_starts_with = get_filters(:string_starts_with, filters, extras)
    string_contains = get_filters(:string_contains, filters, extras)
    list_contains_any = get_filters(:list_contains_any, filters, extras)
    list_contains_all = get_filters(:list_contains_all, filters, extras)

    key_type_docs(filters) <>
      equal_to_docs(equal_to) <>
      equal_to_any_docs(equal_to_any) <>
      smaller_than_docs(smaller_than) <>
      greater_than_or_equal_to_docs(greater_than_or_equal_to) <>
      string_starts_with_docs(string_starts_with) <>
      string_contains_docs(string_contains) <>
      list_contains_docs(list_contains) <>
      list_contains_any_docs(list_contains_any) <>
      list_contains_all_docs(list_contains_all) <>
      order_by_docs(filters[:order_by]) <>
      limit_docs(filters[:limit]) <> offset_docs(filters[:offset])
  end

  ############
  # Privates #
  ############

  # creates a list for use in a guard (only in macro) depending on the caller's key-types opt-ins
  defp create_keylist(definitions, key) do
    cond do
      definitions[:atom_keys] && definitions[:string_keys] -> [key, "#{key}"]
      definitions[:atom_keys] -> [key]
      definitions[:string_keys] -> ["#{key}"]
      true -> raise "One of :atom_keys or :string_keys must be enabled"
    end
  end

  # returns a filter definitions match key as {filter_name, binding_name, field_name}
  defp parse_filter_definition_key({filter, {binding, field}}, _default_binding) do
    {filter, binding, field}
  end

  defp parse_filter_definition_key({filter, field}, default_binding) do
    {filter, default_binding, field}
  end

  defp parse_filter_definition_key(filter, default_binding) do
    {filter, default_binding, filter}
  end

  # adds support for a limit-filter if enabled by the caller
  defp maybe_support_limit(clauses, definitions) do
    if definitions[:limit] do
      add_clause(
        clauses,
        quote(do: {flt, val} when flt in unquote(create_keylist(definitions, :limit))),
        quote(do: limit(query, ^val))
      )
    else
      clauses
    end
  end

  # adds support for an offset-filter if enabled by the caller
  defp maybe_support_offset(clauses, definitions) do
    if definitions[:offset] do
      add_clause(
        clauses,
        quote(do: {flt, val} when flt in unquote(create_keylist(definitions, :offset))),
        quote(do: offset(query, ^val))
      )
    else
      clauses
    end
  end

  # adds support for an order_by-filter if enabled by the caller
  # the order_by filter supports multiple order-by fields
  # equal_to aliases (like `role_name: {:role, :name}`) are resolved as well
  defp maybe_support_order_by(clauses, definitions, def_bnd, resolve_binding) do
    if definitions[:order_by] do
      equal_to_filters =
        (definitions[:equal_to] || [])
        |> Stream.map(&parse_filter_definition_key(&1, def_bnd))
        |> Enum.map(fn {filter_name, bnd, fld} -> {filter_name, {bnd, fld}} end)

      add_clause(
        clauses,
        quote do
          {flt, val} when flt in unquote(create_keylist(definitions, :order_by)) and is_list(val)
        end,
        quote do
          resolve_binding = unquote(resolve_binding)

          Enum.reduce(val, query, fn
            {dir, {bnd, fld}}, q ->
              q |> resolve_binding.(bnd) |> order_by([{^bnd, bd}], [{^dir, field(bd, ^fld)}])

            {dir, fld}, q ->
              {bnd, fld} = Keyword.get(unquote(equal_to_filters), fld, {unquote(def_bnd), fld})

              q
              |> resolve_binding.(bnd)
              |> order_by([{^bnd, bd}], [{^dir, field(bd, ^fld)}])

            fld, q ->
              {bnd, fld} = Keyword.get(unquote(equal_to_filters), fld, {unquote(def_bnd), fld})

              q |> resolve_binding.(bnd) |> order_by([{^bnd, bd}], field(bd, ^fld))
          end)
        end
      )
    else
      clauses
    end
  end

  # add a single clause to the clauses list
  defp add_clause(clauses, clause, block) do
    clauses ++ [{:->, [], [[clause], block]}]
  end

  # add a new clause to the clauses list for each filter definition in the enumerable
  # the reductor must create a new clause from every filter definition
  defp add_clause_for_each(clauses, enumerable, default_binding, reductor) do
    (enumerable || [])
    |> Enum.map(&parse_filter_definition_key(&1, default_binding))
    |> Enum.reduce(clauses, reductor)
  end

  ###################################
  # Documentation generator helpers #
  ###################################

  defp get_filters(type, filters, extras) do
    ([] ++ maybe_get_filters(filters, type) ++ maybe_get_filters(extras, type))
    |> Enum.map(&parse_filter/1)
    |> Enum.sort_by(fn
      {filter_name, _field} -> filter_name
      filter -> filter
    end)
  end

  defp maybe_get_filters(nil, _type), do: []
  defp maybe_get_filters(enum, type), do: enum[type] || []

  defp parse_filter({filter_name, {binding, field}}), do: {filter_name, "#{binding}.#{field}"}
  defp parse_filter(filter), do: filter

  defp key_type_docs(filters) do
    cond do
      filters[:atom_keys] && filters[:string_keys] ->
        """
        ## Filter key types

        Filter keys may be both atoms and strings, e.g. %{username: "Dave123", "first_name" => "Dave"}

        """

      filters[:atom_keys] ->
        """
        ## Filter key types

        Filter keys may only be atoms, e.g. %{username: "Dave123"}

        """

      filters[:string_keys] ->
        """
        ## Filter key types

        Filter keys may only be strings, e.g. %{"first_name" => "Dave"}

        """
    end
  end

  defp equal_to_docs([]), do: ""

  defp equal_to_docs(equal_to) do
    """
    ## Equal-to filters

    The field's value must be equal to the filter value.
    The equivalent Ecto code is
    ```
    where(query, [binding: bd], bd.field == ^filter_value)
    ```
    Additionally, aliases defined in equal-to filters, like `[role_name: {:role, :name}]` can be used in `order_by` as well.
    The following filter names are supported:
    #{equal_to |> to_list()}

    """
  end

  defp equal_to_any_docs([]), do: ""

  defp equal_to_any_docs(equal_to_any) do
    """
    ## Equal-to-any filters

    The field's value must be equal to any of the filter values.
    The equivalent Ecto code is
    ```
    where(query, [binding: bd], bd.field in ^filter_value)
    ```
    The following filter names are supported:
    #{equal_to_any |> to_list()}

    """
  end

  defp list_contains_docs([]), do: ""

  defp list_contains_docs(list_contains) do
    """
    ## List-contains filters

    The array-type field's value must contain the filter's value (set membership).
    The equivalent Ecto code is
    ```
    where(query, [binding: bd], ^filter_value in bd.field)
    ```
    The following filter names are supported:
    #{list_contains |> to_list()}

    """
  end

  defp list_contains_any_docs([]), do: ""

  defp list_contains_any_docs(list_contains_any) do
    """
    ## List-contains-any filters

    The array-type field's value must contain any of the filter's values (set intersection).
    The equivalent Ecto code is
    ```
    where(query, [binding: bd], fragment("? && ?", bd.field, ^val))
    ```
    The following filter names are supported:
    #{list_contains_any |> to_list()}

    """
  end

  defp list_contains_all_docs([]), do: ""

  defp list_contains_all_docs(list_contains_all) do
    """
    ## List-contains-all filters

    The array-type field's value must contain all of the filter's values (subset).
    The equivalent Ecto code is
    ```
    where(query, [binding: bd], fragment("? @> ?", bd.field, ^val))
    ```
    The following filter names are supported:
    #{list_contains_all |> to_list()}

    """
  end

  defp smaller_than_docs([]), do: ""

  defp smaller_than_docs(smaller_than) do
    """
    ## Smaller-than filters

    The field's value must be smaller than the filter's value.
    The equivalent Ecto code is
    ```
    where(query, [binding: bd], bd.field < ^filter_value)
    ```
    The following filter names are supported:

    Filter name | Must be smaller than
    --- | ---
    #{smaller_than |> to_table()}

    """
  end

  defp greater_than_or_equal_to_docs([]), do: ""

  defp greater_than_or_equal_to_docs(greater_than_or_equal_to) do
    """
    ## Greater-than-or-equal-to filters

    The field's value must be greater than or equal to the filter's value.
    The equivalent Ecto code is
    ```
    where(query, [binding: bd], bd.field >= ^filter_value)
    ```
    The following filter names are supported:

    Filter name | Must be greater than or equal to
    --- | ---
    #{greater_than_or_equal_to |> to_table()}

    """
  end

  defp order_by_docs(true) do
    """
    ## Order-by sorting

    Order-by filters do not actually filter the result set, but sort it according to the filter's value(s).

    Order-by filters take a list argument, that can consist of the following elements:
    - `field` will sort on the specified field of the default binding in ascending order
    - `{:direction, :field}` will sort on the specified field of the default binding in the specified direction
    - `{:direction, {:binding, :field}}` will sort on the specified field of the specified binding in the specified direction.

    Note that the value of `order_by` filters must consist of atoms, even with `string_keys` enabled.

    All fields present in the query on any named binding are supported, including field name aliases specified in the filter definitions under equal_to.
    For example, in case of filter definitions `[equal_to: [role_name: {:role, :name}]]`, the following will work: `%{order_by: [desc: :role_name]}`.

    The supported directions can be found in the docs of `Ecto.Query.order_by/3`.

    """
  end

  defp order_by_docs(_), do: ""

  defp limit_docs(true) do
    """
    ## Limit filter

    The `limit` filter sets a maximum for the number of rows in the result set and may be used for pagination.

    """
  end

  defp limit_docs(_), do: ""

  defp offset_docs(true) do
    """
    ## Offset filter

    The `offset` filter skips a number of rows in the result set and may be used for pagination.

    """
  end

  defp offset_docs(_), do: ""

  defp string_starts_with_docs([]), do: ""

  defp string_starts_with_docs(string_starts_with) do
    """
    ## String-starts-with filters

    The string-type field's value must start with the filter's value.
    The equivalent Ecto code is
    ```
    where(query, [binding: bd], ilike(bd.field, ^(val <> "%")))
    ```
    The following filter names are supported:
    #{string_starts_with |> to_list()}

    """
  end

  defp string_contains_docs([]), do: ""

  defp string_contains_docs(string_contains) do
    """
    ## String-contains filters

    The string-type field's value must contain the filter's value.
    The equivalent Ecto code is
    ```
    where(query, [binding: bd], ilike(bd.field, ^("%" <> val <> "%")))
    ```
    The following filter names are supported:
    #{string_contains |> to_list()}

    """
  end

  defp to_list(list) do
    Enum.reduce(list, "", fn
      {filter_name, field}, acc -> "#{acc}* `#{filter_name}` (actual field is `#{field})`\n"
      filter, acc -> "#{acc}* `#{filter}`\n"
    end)
    |> String.trim_trailing("\n")
  end

  defp to_table(keyword) do
    Enum.reduce(keyword, "", fn {k, v}, acc -> acc <> "`#{k}` | `#{v}`\n" end)
    |> String.trim_trailing("\n")
  end
end
