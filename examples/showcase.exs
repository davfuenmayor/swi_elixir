defmodule ProverShowcase do
  @moduledoc "Formula generators and prover examples."
  @all [leancop: :classical, leanhat: :ht, ileancop: :intu]

  def cases do
    [
      %{
        name: "Function chain (4)",
        formula: chain(4),
        modes: @all,
        expected: %{classical: "proved", ht: "proved", intu: "proved"}
      },
      %{
        name: "Function chain (6)",
        formula: chain(6),
        modes: [ileancop: :intu],
        expected: %{intu: "proved"}
      },
      %{
        name: "Three pigeons, two holes",
        formula: pigeon(2),
        modes: @all,
        expected: %{classical: "proved", ht: "proved", intu: "proved"}
      },
      %{
        name: "Pelletier 16: prelinearity",
        formula: "(p=>q);(q=>p)",
        modes: @all,
        expected: %{classical: "proved", ht: "proved", intu: "exhausted"}
      },
      %{
        name: "Pelletier 18: quantified witness",
        formula: "ex Y:all X:(p(Y)=>p(X))",
        modes: @all,
        expected: %{classical: "proved", ht: "proved", intu: "exhausted"}
      },
      %{
        name: "Excluded middle",
        formula: "p; ~p",
        modes: @all,
        expected: %{classical: "proved", ht: "exhausted", intu: "exhausted"}
      },
      %{
        name: "Double-negation elimination",
        formula: "(~ ~p)=>p",
        modes: @all,
        expected: %{classical: "proved", ht: "exhausted", intu: "exhausted"}
      }
    ]
  end

  def chain(n) do
    term = Enum.reduce(1..n, "a", fn _, t -> "f(#{t})" end)
    "(p(a),(all X:(p(X)=>p(f(X)))))=>p(#{term})"
  end

  def pigeon(holes) do
    rows = for p <- 1..(holes + 1), do: "(" <> Enum.map_join(1..holes, ";", &"o#{p}#{&1}") <> ")"

    collisions =
      for h <- 1..holes,
          p <- 1..(holes + 1),
          q <- 1..(holes + 1),
          p < q,
          do: "(o#{p}#{h},o#{q}#{h})"

    "(" <> Enum.join(rows, ",") <> ")=>(" <> Enum.join(collisions, ";") <> ")"
  end

  def goal(prover, logic, formula) do
    quoted = formula |> :json.encode() |> IO.iodata_to_binary()
    "prover_showcase:run(#{prover},#{logic},#{quoted},Result,Calls,Inferences,Proof)"
  end

  def run(session, prover, logic, formula) do
    [answer] = SWI.query(session, goal(prover, logic, formula), timeout: 5_000) |> Enum.to_list()
    true = answer["Calls"] > 0
    true = answer["Inferences"] > 0
    answer
  end
end
