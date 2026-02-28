# Effects

## Effect algebra pattern

Each effect module defines a GADT and uses `makeSem` to generate smart constructors:

```haskell
data MyEffect m a where
  DoThing :: Arg -> MyEffect m Result

makeSem ''MyEffect
```

## Interpreter pattern

**Pure interpreter** (for tests) -- uses `reinterpret` into `State` or `Writer`:

```haskell
myEffectToList :: Sem (MyEffect ': r) a -> Sem r ([Result], a)
myEffectToList =
  fmap (\(xs, a) -> (reverse xs, a))
    . runState []
    . reinterpret (\case DoThing arg -> modify' (result :))
```

**IO interpreter** (for production) -- uses `interpret` with `Embed IO`:

```haskell
myEffectToIO :: (Member (Embed IO) r) => Sem (MyEffect ': r) a -> Sem r a
myEffectToIO = interpret $ \case
  DoThing arg -> embed $ performIO arg
```

## Higher-order effects

Use when an effect needs to wrap other effectful computations (e.g., transactions, resource brackets). Prefer first-order effects when possible.
