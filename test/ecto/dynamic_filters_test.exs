defmodule PhoenixApiToolkit.Ecto.DynamicFiltersTest do
  use ExUnit.Case, async: true
  import PhoenixApiToolkit.Ecto.DynamicFilters
  import Ecto.Query
  require Ecto.Query

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

  def list_without_standard_filters(filters \\ %{}) do
    from(user in "users", as: :user)
    |> apply_filters(filters, fn
      {:order_by, {field, direction}}, query ->
        order_by(query, [user: user], [{^direction, field(user, ^field)}])

      {literal, value}, query when literal in [:id, :name, :residence, :address] ->
        where(query, [user: user], field(user, ^literal) == ^value)

      _, query ->
        query
    end)
  end

  def by_group_name(query, group_name) do
    where(query, [user: user], user.group_name == ^group_name)
  end

  def list_with_standard_filters(filters \\ %{}) do
    from(user in "users", as: :user)
    |> apply_filters(filters, fn
      # Add custom filters first and fallback to standard filters
      {:group_name, value}, query ->
        by_group_name(query, value)

      filter, query ->
        standard_filters(query, filter, :user, @filter_definitions, &resolve_binding/2)
    end)
  end

  def list_order_by_only(filters \\ %{}) do
    from(user in "users", as: :user)
    |> apply_filters(Map.take(filters, [:order_by, "order_by"]), fn filter, query ->
      order_by_only(query, filter, :user, @filter_definitions, &resolve_binding/2)
    end)
  end

  # this is a little helper to update the docs
  # test "generate rendered filter docs" do
  #   ("\n" <> generate_filter_docs(@filter_definitions, equal_to: [:group_name]))
  #   |> String.replace("\n", "\n> ")
  #   |> IO.puts()
  # end

  test "generate filter docs" do
    assert generate_filter_docs(@filter_definitions, equal_to: [:group_name]) ==
             "## Filter key types\n\nFilter keys may be both atoms and strings, e.g. %{username: \"Dave123\", \"first_name\" => \"Dave\"}\n\n## Equal-to filters\n\nThe field's value must be equal to the filter value.\nThe equivalent Ecto code is\n```\nwhere(query, [binding: bd], bd.field == ^filter_value)\n```\nAdditionally, aliases defined in equal-to filters, like `[role_name: {:role, :name}]` can be used in `order_by` as well.\nThe following filter names are supported:\n* `address`\n* `balance`\n* `group_name`\n* `id`\n* `role_name` (actual field is `role.name)`\n* `username`\n\n## Equal-to-any filters\n\nThe field's value must be equal to any of the filter values.\nThe equivalent Ecto code is\n```\nwhere(query, [binding: bd], bd.field in ^filter_value)\n```\nThe following filter names are supported:\n* `address`\n\n## Smaller-than filters\n\nThe field's value must be smaller than the filter's value.\nThe equivalent Ecto code is\n```\nwhere(query, [binding: bd], bd.field < ^filter_value)\n```\nThe following filter names are supported:\n\nFilter name | Must be smaller than\n--- | ---\n`balance_lt` | `balance`\n`inserted_before` | `inserted_at`\n`role_inserted_before` | `role.inserted_at`\n\n## Greater-than-or-equal-to filters\n\nThe field's value must be greater than or equal to the filter's value.\nThe equivalent Ecto code is\n```\nwhere(query, [binding: bd], bd.field >= ^filter_value)\n```\nThe following filter names are supported:\n\nFilter name | Must be greater than or equal to\n--- | ---\n`balance_gte` | `balance`\n`inserted_at_or_after` | `inserted_at`\n\n## String-starts-with filters\n\nThe string-type field's value must start with the filter's value.\nThe equivalent Ecto code is\n```\nwhere(query, [binding: bd], ilike(bd.field, ^(val <> \"%\")))\n```\nThe following filter names are supported:\n* `username_prefix` (actual field is `user.username)`\n\n## String-contains filters\n\nThe string-type field's value must contain the filter's value.\nThe equivalent Ecto code is\n```\nwhere(query, [binding: bd], ilike(bd.field, ^(\"%\" <> val <> \"%\")))\n```\nThe following filter names are supported:\n* `username_search` (actual field is `username)`\n\n## List-contains filters\n\nThe array-type field's value must contain the filter's value (set membership).\nThe equivalent Ecto code is\n```\nwhere(query, [binding: bd], ^filter_value in bd.field)\n```\nThe following filter names are supported:\n* `roles`\n\n## List-contains-any filters\n\nThe array-type field's value must contain any of the filter's values (set intersection).\nThe equivalent Ecto code is\n```\nwhere(query, [binding: bd], fragment(\"? && ?\", bd.field, ^val))\n```\nThe following filter names are supported:\n* `roles`\n\n## List-contains-all filters\n\nThe array-type field's value must contain all of the filter's values (subset).\nThe equivalent Ecto code is\n```\nwhere(query, [binding: bd], fragment(\"? @> ?\", bd.field, ^val))\n```\nThe following filter names are supported:\n* `all_roles` (actual field is `roles)`\n\n## Order-by sorting\n\nOrder-by filters do not actually filter the result set, but sort it according to the filter's value(s).\n\nOrder-by filters take a list argument, that can consist of the following elements:\n- `field` will sort on the specified field of the default binding in ascending order\n- `{:direction, :field}` will sort on the specified field of the default binding in the specified direction\n- `{:direction, {:binding, :field}}` will sort on the specified field of the specified binding in the specified direction.\n\nNote that the value of `order_by` filters must consist of atoms, even with `string_keys` enabled.\n\nAll fields present in the query on any named binding are supported, including field name aliases specified in the filter definitions under equal_to.\nFor example, in case of filter definitions `[equal_to: [role_name: {:role, :name}]]`, the following will work: `%{order_by: [desc: :role_name]}`.\n\nThe supported directions can be found in the docs of `Ecto.Query.order_by/3`.\n\n## Limit filter\n\nThe `limit` filter sets a maximum for the number of rows in the result set and may be used for pagination.\n\n## Offset filter\n\nThe `offset` filter skips a number of rows in the result set and may be used for pagination.\n\n"
  end

  doctest PhoenixApiToolkit.Ecto.DynamicFilters
end
