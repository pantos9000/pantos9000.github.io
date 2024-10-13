+++
title = "How safe rust avoids pointer aliasing"
date = 2024-06-06

[taxonomies]
tags = ["rust", "unsafe", "aliasing", "ub"]

[extra]
toc = true
+++

# Introduction

Recently I read a
[very interesting article](https://developers.redhat.com/blog/2020/06/02/the-joys-and-perils-of-c-and-c-aliasing-part-1)
that is discussing problems that can arise with
[pointer aliasing](https://doc.rust-lang.org/nomicon/aliasing.html).
While reading it, I realized that safe Rust is elegantly avoiding these problems inherently.

Aliasing is basically when two pointers point to the same or parts of the same data or allocation.
When you have two pointers of the same data type, the compiler does not know if these might point
to the same data, or if they are completely distinct. This becomes relevant as soon as the compiler
is trying to do certain optimizations.


# A simple example

Assume we have two similar structs:

```rust
struct Foo {
    foo: i32,
}

struct Bar {
    bar: i32,
}
```

As both structs have the exact same memory layout, `Foo` can also be interpreted as `Bar`. This
could be used for a very efficient conversion function:

```rust
impl Bar {
    fn from_foo(foo: *mut Foo) -> *mut Self {
        // ok because Foo and Bar have the same memory layout
        foo.cast()
    }
}
```

This is very often used in lower-level languages like *C*. In Rust you don't see it that often, but
it can sometimes also become relevant, especially in
[ffi contexts](https://doc.rust-lang.org/nomicon/ffi.html).

Further assume that we have a function that uses both structs. It sets the internal values of both
structs and returns the internal value of the first. Note that here, raw pointers are used for the
sake of example, as with safe rust we can't run into these kind of problems.

```rust
unsafe fn set_both_and_return_first(foo: *mut Foo, bar: *mut Bar) -> i32 {
    (*foo).foo = 42;
    (*bar).bar = 43;

    // we can return 42 as we know first is set to 42
    // (foo and bar must not alias)
    42
}
```


## Where things go wrong

As mentioned previously, there is a problem with this optimization: `Bar` can be constructed from
a `Foo`, so `foo` and `bar` can point to the same data. But if this is the case, returning `42`
would be wrong, as callers would expect that it is overwritten and `43` will be returned.

So let's try to fix this by removing the optimization:

```rust
unsafe fn set_both_and_return_first(foo: *mut Foo, bar: *mut Bar) -> i32 {
    (*foo).foo = 42;
    (*bar).bar = 43;

    (*foo).foo
}
```

But remember that the compiler can actually do its own optimizations. The compiler can assume that
no aliasing is happening, as the two types are different, and apply the very same optimization.

Aliasing behavior can be controlled with the `-Zmutable-noalias` compiler parameter.
[At some point it was set to `no` by default](https://stackoverflow.com/questions/57259126/why-does-the-rust-compiler-not-optimize-code-assuming-that-two-mutable-reference),
so the compiler would assume aliasing might happen and thus skip certain optimizations, but
[this is no longer true](https://github.com/rust-lang/rust/issues/54878#issuecomment-803880176).
Nowadays the compiler **does** assume by default that no aliasing is happening, so the optimization
above would be legal for it to apply.


## The easy way out

Currently, the Rust compiler does not apply this optimization, even if it is allowed to. But it
could at some point, so the above code might break e.g. when updating the compiler version.

One way to tackle this problem is of course to explicitly set `-Zmutable-noalias=no`, but this has
the huge drawback that we can't just easily re-use the code in some other project, that might not
have this flag set. Or we might forget setting it and run into the same problems again.


## A better way out

There is another option to make sure no problem occurs: We can make it part of the function contract
that no aliasing may occur. In other words, callers have to make sure that no aliasing occurs when
calling the function.

In Rust, this is usually done with `Safety` blocks in the function docs:

```rust
/// Write to both structs and return the value of the first struct (foo) afterwards.
///
/// # Safety
/// * Pointers must not be NULL
/// * Pointers must not alias
/// * Pointers must point to valid data
unsafe fn set_both_and_return_first(foo: *mut Foo, bar: *mut Bar) -> i32 {
    // ...
}
```

Furthermore, callers can add a `SAFETY` comment to indicate what they took into account to make
calling the function sound:

```rust
    let mut foo = Foo::default();
    let bar = Bar::from_foo(&mut foo);

    // SAFETY:
    // * Pointers are not null, created from reference
    // * Pointer data is valid, created from reference
    let foo_val = unsafe { set_both_and_return_first(foo_raw, bar_raw) };
```

When reviewers stumble across this code, they can immediately see what the developer took into
account and what he did not.

When looking at this particular call and the docs of the function, it will become clear that
the aliasing invariant was forgotten - both pointers clearly alias when creating a `Bar` raw
pointer with `from_foo()`.

This kind of documentation makes it very easy to spot these kind of bugs. A nice thing to keep in
mind is that providing it can be enforced with the clippy lints
[missing_safety_doc](https://rust-lang.github.io/rust-clippy/master/index.html#/missing_safety_doc)
and
[undocumented_unsafe_blocks](https://rust-lang.github.io/rust-clippy/master/index.html#/undocumented_unsafe_blocks).


# Performance implications

The [second part of the article mentioned above](https://developers.redhat.com/blog/2020/06/03/the-joys-and-perils-of-aliasing-in-c-and-c-part-2)
makes another interesting point: The compiler assumes that aliasing can occur for "compatible
pointers", while for "incompatible types", it will assume it can not.

The `C` and `C++` standard defines that two pointers are "compatible" if they have the same type.
But as the access to all data is also allowed via `char*` pointers, those also are always
considered "compatible".

So as soon as a function has a `char*` parameter that is written to, the compiler will assume that
aliasing can occur and avoid certain optimizations. This is even true if you have wrapping types
like `Vector` or `String`, e.g. when you write to a passed `&String` parameter.


# How safe rust elegantly avoids aliasing

Usually, you would use safe rust for a function like this:

```rust
fn set_both_and_return_first(foo: &mut Foo, bar: &mut Bar) -> i32 {
    foo.foo = 42;
    bar.bar = 43;
    foo.foo
}
```

But as `foo` and `bar` are mutably borrowed,
[no other existing references to the data are allowed](https://doc.rust-lang.org/book/ch04-02-references-and-borrowing.html).
Thus, no aliasing can ever
occur in safe Rust, as we are never allowed to create another reference to the same data.

