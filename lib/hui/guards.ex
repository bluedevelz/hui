defmodule Hui.Guards do
  @moduledoc false
  defguard is_nil_empty(value) when value == "" or is_nil(value) or length(value) == 0
end
