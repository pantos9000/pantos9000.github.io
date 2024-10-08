+++
title = "An unsound cell implementation"
date = 2024-05-08

[taxonomies]
tags = ["rust", "subtyping", "variance", "ub"]

[extra]
toc = true
+++

# Introduction

I recently came across [this RustFest 2016 talk](https://www.youtube.com/watch?v=fI4RG_uq-WU&t=1554s)
giving an example of a manual [cell](https://doc.rust-lang.org/std/cell/) implementation that is
inherently unsound.

Let's look at this short example:

```rust
pub struct MyCell<T: Copy> {
    value: T,
}

impl<T: Copy> MyCell<T> {
    pub fn new(value: T) -> Self {
        Self { value }
    }

    pub fn get(&self) -> T {
        self.value
    }

    #[allow(invalid_reference_casting)] // don't do this at home, kids...
    pub fn set(&self, value: T) {
        let value_ptr = std::ptr::from_ref(&self.value).cast_mut();
        unsafe {
            std::ptr::write(value_ptr, value);
        }
    }
}
```

Pretty straight forward - our cell is holding a value, that we can `set()`, despite the fact that
`self` is immutable. We do this by getting a reference to the contained value, create a `*const`
raw pointer from it, and cast that to its mutable version `*mut`. This is then used to directly
overwrite the value inside an `unsafe` block.

This is unsound for two reasons.

# Reason #1: Subtyping? What subtyping?

Consider the following test:

```rust
#[test]
fn this_is_fine() {
    static STATIC_INT: i32 = 10;

    // cell is supposed to hold a static ref
    let cell: MyCell<&'static i32> = MyCell::new(&STATIC_INT);

    // enter a new scope
    {
        let newval = 13;
        // Cell value is set to non-static ref
        cell.set(&newval);
    }
    // we leave the scope, newval is freed and not valid anymore

    assert_eq!(cell.value, &13); // now cell ref is dangling, use-after-free :(
}
```

This does not seem right...

The cell content was set to the reference to `newval`, even though it should only hold references
with `static` lifetime... Even worse, the reference can still be used after its referenced value
is freed!

So this test should fail hard, right? Well, let's try to...


## Execute the test

We run it with `cargo test`:

```text
running 1 test
test tests::this_is_fine ... ok
```

Wow, this does not even fail! What the decoherence is going on?

Well, when looking at the comments in the test, we see that we got us a neat use-after-free bug.
I still remember getting PTSD from those when I was still coding C - the memory is freed, but the
content is still there! We read it, even though we should not be able to, and the test succeeds.
But on other occasions, the memory content might have changed.

Let's try to verify this by running `cargo test --release`:

```text
running 1 test
test tests::this_is_fine ... FAILED

failures:

---- tests::this_is_fine stdout ----
thread 'tests::this_is_fine' panicked at src/lib.rs:42:9:
assertion `left == right` failed
  left: 0
 right: 13
```

A-ha! So the implementation of `MyCell` really is broken. The borrow checker left us stranded in
the desert, letting us compile this junk. But why?


## Covariance

The reason why assigning a *non-static* reference to a `MyCell` holding a *static* reference is
possible because `MyCell<T>` is *covariant* over `T`.

Looking at the [rustonomicon link](https://doc.rust-lang.org/nomicon/subtyping.html),
**Covariance** means:
> If `T` is subtype of `U`, `MyCell<T>` will be a subtype of `MyCell<U>`.

What? Subtypes? I thought Rust does not have that? Well, not quite - subtyping is used with
lifetimes, in order to enable us to use a "more useful" lifetime (covering a bigger region) in a
place where only a "less useful" lifetime (covering a smaller region) is required. This is the
reason why
> `'static` is always subtype of any `'a`.

Covariance is assumed (see rustonomicon table above), because `T` is owned by `MyCell`. But with
`MyCell<T>` being covariant over `T`, this means that when a `MyCell<'a>` is required, we can also
use a `MyCell<'static>`. Furthermore, immutable references are also covariant. So when a
`&MyCell<'a>` is required, a `&MyCell<'static>` will do.

Let's look again at the signature of `set()`:

```rust
pub fn set(&self, value: T)
```

When T is `'a`, then `&self` has to be `&MyCell<'a>`. But as we learned, Rust is also fine with
`&MyCell<'static>` in its place, as it thinks it is "more useful". So this is why assigning a
lifetime `'a` to `MyCell<'static>` works!

Note that *mutable references* are **not covariant**, but **invariant** over `T`. So when using
`&mut self` instead, the above does not apply. As the "covariance-chain" is interrupted, the
compiler won't accept `MyCell<'a>` and reject the above code:

```text
38 |             cell.set(&newval);
   |                      ^^^^^^^ borrowed value does not live long enough
```

So how can we fix this, without requiring a mutable `self`?


## PhantomData to the rescue

With [PhantomData](https://doc.rust-lang.org/std/marker/struct.PhantomData.html), we can have an
additional member in `MyCell`, that prevents the struct from being covariant over `T`. This won't
add any more actual data to our struct, but will change the way the compiler treats it.

When we check the table [in the rustonomicon](https://doc.rust-lang.org/nomicon/phantom-data.html),
we can see that we can use one of:

* `PhantomData<*mut T>`
* `PhantomData<fn(T) -> T>`

Both make our struct invariant over `T`, the main difference is if the struct should be
[Send and Sync](https://doc.rust-lang.org/nomicon/send-and-sync.html) or not. As we want to tackle
the problem at hand and not agonize over multithreading, we will pick `PhantomData<*mut T>`.

```rust
pub struct MyCell<T> {
    value: T,
    _phantom: std::marker::PhantomData<*mut T>,
}

impl<T: Copy> MyCell<T> {
    pub fn new(value: T) -> Self {
        Self {
            value,
            _phantom: std::marker::PhantomData,
        }
    }

    pub fn get(&self) -> T {
        self.value
    }

    #[allow(invalid_reference_casting)] // UB even with proper variance. But for the sake of example...
    pub fn set(&self, value: T) {
        use std::ptr;
        let value_ptr = std::ptr::from_ref(&self.value).cast_mut();
        unsafe {
            ptr::write(value_ptr, value);
        }
    }
}
```

Now this looks promising! When running `cargo test`, the compiler will refuse the test and give
us the same error as before:

```text
43 |             cell.set(&newval);
   |                      ^^^^^^^ borrowed value does not live long enough
```

We did it, we fixed our `Cell` implementation! We are done now, right?

Right...?



# Reason #2: Nasal demons

[Nope](https://en.wikipedia.org/wiki/Nasal_demons).

There is a nasty thing called **Undefined Behavior**, about which I will probably do an extra blog
post in the future. But here is a short explanation, despite my C PTSD coming back again...

## A quick overview

There is a contract between you and the compiler. You are only allowed to do certain things, and
so does the compiler. If you do a mistake, the compiler is obliged to complain and not compile the
program. But when you do stuff that is considered **UB** by the standard, the compiler is not
obliged to do anything. It can do what it wants! It might nag at you, or just compile the program,
but change the actual commands that are executed. Like formatting your hard drive.

Well, usually it doesn't. The compiler creators are on your side (and they use their tool
themselves), so they won't put harmful behavior in there. But your **UB** infested program might
just do something that is not described by the source code. Or maybe it will at first, but will do
something different after a compiler update. Considering this behavior, you see that it is actually
very troublesome to detect **UB**, because your programming compiling and working like it should
does not necessarily mean that your code is sound.

## UB in our implementation

Luckily, you can't run into **UB** when sticking to *safe rust*, but as we use unsafe blocks, we
have to take extra care.

Looking at Rust's [list of things considered UB](https://doc.rust-lang.org/reference/behavior-considered-undefined.html),
we can identify one problem: The mutation of bytes pointed to by a shared (i.e. immutable)
reference. The only exception allowed is inside an
[UnsafeCell](https://doc.rust-lang.org/std/cell/struct.UnsafeCell.html).

This means that the compiler implicitly "knows" that data inside an (immutably referenced)
`UnsafeCell` might be mutated, while this is not the case with our implementation.

Actually the compiler would have detected the **UB** and would have complained, and even proposed
to use an [unsafe cell](https://doc.rust-lang.org/std/cell/struct.UnsafeCell.html). But for the
sake of example, we used the `#[allow]` statement to disable the error, to be able to tinker around
with the unsound implementation. If we remove it, our code won't compile. Nice!

# Miri to the rescue

There might be other cases that are not as obvious as the one shown here. To detect several
different forms of **UB**, we can use the very neat tool [Miri](https://github.com/rust-lang/miri).

First let's delete the previous test and add a new one:

```rust
    #[test]
    fn this_is_even_finer() {
        let cell = MyCell::new(10);
        let newval = 13;
        cell.set(newval);
        assert_eq!(cell.value, 13);
    }
```

Install Miri with

```bash
rustup +nightly component add miri
```

Run Miri with

```bash
cargo +nightly miri test
```

This gives us the following error:

```text
running 1 test
test tests::this_is_also_fine ... error: Undefined Behavior: attempting a write access using
<178867> at alloc62087[0x0], but that tag only grants SharedReadOnly permission for this location
```

So even with the fix, our implementation is still unsound. But at least now we know why and how
to detect these kind of errors.

# A final try

Apart from the possibility of using `UnsafeCell` and just going down the path of the stdlib, we
have another option: We can store a raw pointer to the data and use it for access.

```rust
pub struct MyCell<T: Copy> {
    value: *mut T,
}

impl<T: Copy> Drop for MyCell<T> {
    fn drop(&mut self) {
        // SAFETY: is created from a Box in constructor
        let value = unsafe { Box::from_raw(self.value) };
        drop(value);
    }
}

impl<T: Copy> MyCell<T> {
    pub fn new(value: T) -> Self {
        let value = Box::new(value);
        let value = Box::into_raw(value);
        Self { value }
    }

    pub fn get(&self) -> T {
        // SAFETY:
        // * value is created in constructor and freed in drop, has to be valid
        // * value is created from a Box, so has to be aligned and properly initialized
        unsafe { std::ptr::read(self.value) }
    }

    pub fn set(&self, value: T) {
        use std::ptr;
        unsafe {
            ptr::write(self.value, value);
        }
    }
}
```

When running the above test with Miri, it does not find any UB. And when trying to compile the
dangling pointer test, it actually does not compile, nice!

But this has a big drawback: Instead of having the data on the stack, it is now stored on the heap.
Not only does this mean we always have to do an additional indirection and follow a pointer, it can
also be quite bad for cache efficiency.

## Variance yet again

As a sidenote, we could also use a `*const` instead of a `*mut` to store `value`. Casting a
`*const` raw pointer to a `*mut` and writing to it is actually not considered UB, as there is no
*immutable reference* (i.e. `&T`) pointing to the data while it is mutated.

But with `*const`, the unsound test from above would compile again. You guessed it - because
`*const` is covariant over `T`. We can fix it the same way again, by adding `PhantomData`:

```rust
pub struct MyCell<T: Copy> {
    value: *const T,
    _phantom: std::marker::PhantomData<*mut T>,
}

impl<T: Copy> Drop for MyCell<T> {
    fn drop(&mut self) {
        // SAFETY: is created from a Box in constructor
        let value = unsafe { Box::from_raw(self.value.cast_mut()) };
        drop(value);
    }
}

impl<T: Copy> MyCell<T> {
    pub fn new(value: T) -> Self {
        let value = Box::new(value);
        let value = Box::into_raw(value);
        Self {
            value,
            _phantom: std::marker::PhantomData,
        }
    }

    pub fn get(&self) -> T {
        // SAFETY:
        // * value is created in constructor and freed in drop, has to be valid
        // * value is created from a Box, so has to be aligned and properly initialized
        unsafe { std::ptr::read(self.value) }
    }

    pub fn set(&self, value: T) {
        use std::ptr;
        unsafe {
            ptr::write(self.value.cast_mut(), value);
        }
    }
}
```

But as using `*mut` achieves the same, there is no real reason using `*const` with `Phantomdata`.
