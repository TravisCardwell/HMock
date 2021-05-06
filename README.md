# HMock - A Flexible Mock Framework for Haskell

HMock provides a flexible mock framework for Haskell, with similar functionality
to Mockito for Java, GoogleMock for C++, and other mainstream languages.

## Quick Start

1.  Define classes for the functionality you need to mock.  To mock anything
    with HMock, it needs to be implemented using a `Monad` subclass.

    ``` haskell
    import Prelude hiding (readFile, writeFile)
    import qualified Prelude

    class MonadFilesystem m where
      readFile :: FilePath -> m String
      writeFile :: FilePath -> String -> m ()

    instance MonadFilesystem IO where
      readFile = Prelude.readFile
      writeFile = Prelude.writeFile
    ```

2.  Implement the code to test, using this class.

    ``` haskell
    copyFile :: MonadFilesystem m => FilePath -> FilePath -> m ()
    copyFile a b = readFile a >>= writeFile b
    ```

3.  Make the class `Mockable` using the provided Template Haskell splices.

    ``` haskell
    makeMockable ''MonadFilesystem
    ```

4.  Set up expectations and run your code.

    ```haskell
    test_copyFile :: IO ()
    test_copyFile = runMockT $ do
      mock $ expect $ readFile_ "foo.txt" |-> "contents"
      mock $ expect $ writeFile_ "bar.txt" "contents" |-> ()

      copyFile "foo.txt" "bar.txt"
    ```

    * `runMockT` runs code in the `MockT` monad transformer.
    * `mock` adds an expectation or rule to the test.
    * `expect` expects a method to be called exactly once.
    * `readFile_` and `writeFile_` match the function calls.  They are defined
      by `makeMockable`.
    * `|->` separates the method call from its result.

## Why mocks?

Mocks are not always the right tool for the job, but they play an important role
in testing practice.

* If possible, we prefer to test with actual code.  Haskell encourages writing
  much of the application logic with pure functions, which can be trivially
  tested.  However, this isn't all of the code, and bugs are quite likely to
  appear in glue code that connects the core application logic to its outside
  effects.

* If testing the actual code is not possible, we prefer to test with high
  quality fake implementations.  These work well for relatively simple effects.
  However, they are difficult to maintain when the behavior of an external
  system is complex, poorly specified, and/or frequently changing.  Incomplete
  or oversimplified fakes can make some of the most bug-prone code, such as
  error handling and unusual cases, very difficult to test.

* Use of a mock framework allows a programmer to test code that uses complex
  effectful interfaces, including all of the dark corners where nasty bugs tend
  to hide.  They also help to isolate test failures: when a component is broken,
  one test fails and is easy to find, rather than everything downstream failing
  at once.

## Why HMock?

HMock was designed to help Haskell programmers adopt good habits when testing
with mocks.  When testing with mocks, two dangers to look out for are
over-assertion and over-stubbing.

**Over-assertion** happens when your test requires things you don't care about.
If you read two files, you usually don't care which order they are read in, so
your tests should pass with either order.  Even when your code needs to behave
a certain way, you usually don't want to check that in every single test.  Each
test should also ideally test one property.  However, a simplistic approach to
mocks may force you to over-assert just to run your code at all.

**Over-stubbing** happens when you remove too much functionality from your code,
and end up assuming part of the logic you intended to test.  This makes your
test less useful.  Again, a simplistic approach to mocks can lead you to stub
too much by not providing the right options for the behavior of your methods.

HMock is designed to help you avoid these mistakes, by offering:

### Flexible ordering

With HMock, you choose which constraints to enforce on the order of methods.
If certain methods need to happen in a fixed sequence, you can use `inSequence`
to check that.  But if you don't care about the order, you need not check it.
If you don't care about certain methods at all, `whenever` will let you set a
response without limiting when they are called.  Using `expectN`, you can make
a method optional, or limit the number of times it can occur.

These tools let you express more of the exact properties you intend to test, so
that you don't fall into the over-assertion trap.

### Flexible matchers

In HMock, you specify exactly what you care about in method parameters, by
using `Predicate`s.  A `Predicate a` is essentially `a -> Bool`, except that it
can be printed for better error messages.  If you want to match all parameters
exactly, there's a shortcut for doing so.  But you can also ignore arguments you
don't care about, or only make partial assertions about their values.  For
example, you can match a keyword in a logging message, without needing to copy
and paste the entire string into your test.

Because you need not compare every argument, HMock can be used to mock methods
whose parameters have no `Eq` instances.  You can write a mock for a method that
takes a function as an argument, for example.  You can even mock polymorphic
methods.

### Flexible responses

In HMock, you have a lot of options for what to do when a method is called.
For example:

1. You can look at the arguments.  Need to return the third argument?  No
   problem; just look at the `Action` that's passed in.
2. You can invoke other methods.  Need to forward one method to another?  Want
   to set up a lightweight fake without defining a new type and instance?  It's
   easy to do so.
3. You can add additional expectations.  Need to be sure that every opened file
   handle is closed?  The respone runs in `MockT`, so just add that expectation
   when the handle is opened.
4. You can perform actions in a base monad.  Need to modify some state for a
   complex test?  Need to keep a log of info so that you can assert a property
   at the end of the test?  Just run your test in `MockT (State Foo)` or
   `MockT (Writer [Info])`, and call `get`, `put`, and `tell` from your
   responses.

These flexible responses help you to avoid over-stubbing.  You can even set up
lightweight fakes using HMock to delegate, and not only does this avoid defining
a new type for each fake instance, but you can also easily inject errors and
other unusual behavior as exceptions to the fake implementation.

### Reusable mocks

With HMock, your mocks are independent of the specific monad stack or
combination of interfaces that your code uses.  You can write tests using any
combination of `Mockable` classes, and each part of your test code depends only
on the classes that you use directly.  This frees you to share convenience
libraries for testing, and reuse these components in different combinations
as needed.

## FAQ

Here are a few tips for making the most of HMock.

### What is the difference between `|->` and `:->`?

In the most general form, an HMock rule contains a response of the form
`Action ... -> MockT m r`.  The action contains the parameters, and the `MockT`
monad can be used to add expectations or do things in the base monad.  You can
build such a rule from a `Matcher` and a response using `:->`.

However, it's very common that you don't need this flexibility, and just want
to specify the return value.  In that case, you can use `|->` instead to keep
things a bit more readable.  Basically, `m |-> r` is just a shorthand for
`m :-> const (return r)`.

### What is the difference between `foo`, `foo_`, `Foo`, and `Foo_`?

These four names have subtly different meanings:

* `foo` is the method of your own class.  This is what is used in the code that
  you are testing.
* `Foo` is an `Action` constructor representing a call to the method.  You will
  typically use this in two places: as the argument to `mockMethod`, and as the
  argument to a response.
* `foo_` constructs a simple `Matcher` with exact arguments.  This is a
  top-level function generated by `makeMockable` or `deriveMockable` when the
  arguments are simple enough to match them exactly.
* `Foo_` is the `Matcher` constructor, and expects `Predicate`s that can match
  the arguments in more general ways without specifying their exact values.
  This is more powerful, but a bit wordier, than using `foo_`.

### Can I mock only some methods of a class?

Yes!

The `makeMockable` splice is the simple way to set up mocks for a class, and
delegates everything in the class to HMock to match with expectations.  However,
sometimes you either can't or don't want to delegate all of your methods to
HMock.  In that case, you'll use the `deriveMockable` splice, instead.  This
implements most of the mock functionality everywhere it's possible for HMock to
do so, but doesn't define the instance for `MockT`.  You will define that
yourself using `mockAction`.

For example:

``` haskell
class MonadFoo m where
  mockThis :: String -> m ()
  butNotThis :: Int -> m String

deriveMockable ''MonadFoo

instance (Monad m, Typeable m) => MonadFoo (MockT m) where
  mockThis x = mockAction (MockThis x)
  butNotThis _ = return "fake, not mock"
```

If your class has members that HMock cannot handle, then you **must** use
`deriveMockable` instead of `makeMockable`.  These include things like
associated types, methods with a return value not in the monad, or methods with
universally quantified return values.

### How do I mock methods with polymorphic arguments?

HMock can be used to write mocks with polymorphic arguments, but there are a few
quirks to keep in mind.

First, let's distinguish between two types of polymorphic arguments.  Consider
this class:

``` haskell
class MonadPolyArgs a m where
  foo :: a -> m ()
  bar :: b -> m ()
```

In `foo`, the argument type `a` is bound by the *instance*.  Instance-bound
arguments act just like concrete types, for the most part, but check out the
question about multi-parameter type classes.

In `bar`, the argument type `b` is bound by the *method*.  Because of this, the
`Matcher` for `bar` will be assigned the rank-n type
`(forall b. Predicate b) -> Matcher ...`.  In fact, pretty much the only
`Predicate` you could use in such a type is `anything` (which always matches, no
matter the argument value).  Since `eq` is not legal here, an exact matcher
function `bar_` will not even be generated.

In order to write a more specific predicate, you'd need to add constraints to
`bar` in the original class.  Understandably, you may be reluctant to modify
your functional code for the sake of testing, but in this case there is no
alternative.  If `bar` can be modified to add `Eq b` and `Show b` as
constraints, then an exact matcher will be generated.  If `bar` can be modified
to add a `Typeable` constraint, then you can use a predicate like
`typed @Int (lt 5)`, which will only match calls where `b` is `Int` (and also
less than 5).

### How do I mock methods with polymorphic return types?

Again, we can distinguish between type variables bound by the instance versus
the method.  Variables bound by the instance work much the same as concrete
types, but check out the question about multi-parameter type classes.

Unfortunately, you cannot use HMock to mock a method with a return type bound
by the method.  HMock will not generate an `Action` or `Matcher` for this
method.  Instead, you will need to write the instance for `MockT` on your own,
as described in the question about partial mocks, and provide a fake
implementation for the problematic method.

### How do I mock multi-parameter type classes?

In order to mock a multi-parameter type class, the monad argument `m` must be
the last type variable.  Then just use `makeMockable ''MonadMPTC`.

### How do I mock classes with functional dependencies?

We will consider classes of the form

``` haskell
class MonadMPTC a m | m -> a
```

If you try to use `makeMockable ''MonadMPTC`, as described in the previous
question, it will not succeed.  The functional dependency requires that `a` is
determined by `m`, but `makeMockable` does not know how to choose `a` correctly
for the `MockT` instance.

You have two choices here:

* **Specialize**: Use `makeMockableType [t| MonadMPTC String |]` to set up HMock
  only when `a ~ String`, which satisfies the functional dependency.  However,
  it's a bit anti-modular, since any other test with `a ~ Int` cannot be
  imported in the same places as this one.
* **Define a base monad**: Use `deriveMockable ''MonadMPTC` to derive the
  `Mockable` instance for `MonadMPTC a`, but not the instance
  `MonadMPTC a (MockT m)` that would violate the functional dependency.  Now, to
  distinguish between different parameters, you will need to define your own
  base monad, then define your own instance for `MockT (MyBase m)`.

  ``` haskell
  class MonadMPTC a m | m -> a where
    foo :: a -> m ()

  deriveMockable ''MonadMPTC

  newtype StringBase m a = StringBase {runStringBase :: m a}
    deriving (Functor, Applicative, Monad)

  instance
    (Monad m, Typeable m) =>
    MonadMPTC String (MockT (StringBase m))
    where
    foo x = mockMethod (Foo x)
  ```

### How do I get better stack traces?

HMock is compatible with stack traces using `HasCallStack`.  These can be very
convenient for find out where your code went wrong and did the wrong thing.
However, the stack traces are mostly useless unless you add a `HasCallStack`
constraint to the methods of your class.

This is unfortunate, but not really avoidable with the current state of Haskell.
You can add the constraint when troubleshooting, and remove it again when you
are done.

### How do I migrate from `monad-mock`?

To mock a class in monad-mock, you could use the Template Haskell `makeAction`
splice.  With HMock, you use `makeMockable` instead.  Unlike `makeAction`, you
write a separate `makeMockable` for each class you intend to mock, and the
generated code is usable with any combination of other classes in the same
tests.

So where you may have previously written:

``` haskell
makeAction ''MyAction [ts| MonadFilesystem, MonadDB |]
```

You will now write:

``` haskell
makeMockable ''MonadFilesystem
makeMockable ''MonadDB
```

To convert a test using monad-mock into a test using HMock, move expectations
from a list outside of `MockT` to a `mock` call inside `MockT`.  To preserve the
exact behavior of the old test, use `inSequence`.  You'll also need to change
your old action constructors to exact `Matcher`s, and change `:->` to `|->`.

If you previously wrote:

``` haskell
runMockT
  [ ReadFile "foo.txt" :-> "contents",
    WriteFile "bar.txt" "contents" :-> ()
  ]
  (copyFile "foo.txt" "bar.txt")
```

You will now write this:

``` haskell
runMockT $ do
    mock $ inSequence
      [ expect $ readFile_ "foo.txt" |-> "contents",
        expect $ writeFile_ "bar.txt" "contents" |-> ()
      ]
    copyFile "foo.txt" "bar.txt"
```

You may now begin to remove assertions that you aren't intending to test.  For
example, `inSequence` is overkill here, since the sequence is just a consequence
of data dependencies.  (Think of it this way: if it were magically possible for
`writeFile` to be called with the right arguments but without waiting on the
`readFile`, it would be correct to do so!  So the order is a consequence of the
implementation, not the specification.)  You can remove the `inSequence` and add
two independent expectations, instead.

``` haskell
runMockT $ do
    mock $ expect $ readFile_ "foo.txt" |-> "contents"
    mock $ expect $ writeFile_ "bar.txt" "contents" |-> ()
    copyFile "foo.txt" "bar.txt"
```

And you're done.