defmodule SWI.Term do
  @moduledoc "Decodes Prolog values without creating BEAM atoms from query data."

  def decode(%{"t" => "atom", "v" => value}) when is_binary(value), do: {:atom, value}
  def decode(%{"t" => "var", "v" => id}) when is_integer(id) and id >= 0, do: {:var, id}
  def decode(%{"t" => "number", "v" => value}) when is_number(value), do: value
  def decode(%{"t" => "string", "v" => value}) when is_binary(value), do: value

  def decode(%{"t" => "list", "v" => values}) when is_list(values),
    do: Enum.map(values, &decode/1)

  def decode(%{"t" => "cons", "v" => [head, tail]}), do: {:cons, decode(head), decode(tail)}

  def decode(%{"t" => "compound", "f" => name, "v" => args})
      when is_binary(name) and is_list(args),
      do: {:compound, name, Enum.map(args, &decode/1)}

  def decode(%{"t" => "prolog", "v" => text}) when is_binary(text), do: {:prolog, text}
end
