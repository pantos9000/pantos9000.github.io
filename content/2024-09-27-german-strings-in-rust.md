+++
title = "German Strings in Rust"
date = 2024-09-27

[taxonomies]
tags = ["Rust", "String", "Memory", "Representation", "Alignment", "Layout"]

[extra]
toc = true
+++

This [very interesting article]( https://tunglevo.com/note/an-optimization-thats-impossible-in-rust/)
describes the very impressive way of how to implement German Strings in Rust - Strings that are
allocated on the stack if they are short enough. Read the articles for details, here I will only
quickly note down my thoughts and tinkering a bit.

The main problem that article is solving is Rust's struct memory layout. As the main point of
implementing that new string is performance, the layout of it should be as concise and small as
possible, without wasting any space.

I will quickly go over the different challenges that the article's authors tackled.

# Alignment

Looking at the [Rust memory layout rules](https://doc.rust-lang.org/reference/type-layout.html),
we can see that each struct has an alignment. If a struct consists of different alignments, the
biggest one is chosen.

As a quick example, assume the following structs:

```Rust
struct Foo {
    x: u32,
    bar: Bar,
}

struct Bar {
    len: u32,
    buf: [u8; 8],
}
```

We can check the size and alignment with `std::mem::size_of()` and `std::mem::align_of()`, reporting
us a size of 16 for `Foo` and a size of 12 for `Bar`, both having an alignment of 4.

Next, we exchange `buf` in `Bar`:

```Rust
struct Bar {
    len: u32,
    val: u64,
}
```

Technically, it has the same size, but a `u64` has an alignment of 8! This results in a padding
inserted in our structs by the compiler, making them bigger. `Foo` now has a size of 24, `Bar`
has 16. Both have an alignment of 8 now.

We can tell Rust to apply a different alignment though:

```Rust
#[repr(packed(4))]
struct Bar {
    len: u32,
    val: u64,
}
```

Now it is back to the original size with 16 and 12. But this has a huge drawback: If we try to
create a reference to `val`, the compiler will nag at us:

```text
error[E0793]: reference to packed field is unaligned
  --> src/main.rs:24:15
   |
24 |     let val = &foo._bar.val;
   |               ^^^^^^^^^^^^^^
   |
   = note: packed structs are only aligned by one byte, and many modern architectures penalize
           unaligned field accesses
   = note: creating a misaligned reference is undefined behavior (even if that reference is never
           dereferenced)
   = help: copy the field contents to a local variable, or replace the reference with a raw pointer
           and use `read_unaligned`/`write_unaligned` (loads and stores via `*p` must be properly
           aligned even when using raw pointers)

For more information about this error, try `rustc --explain E0793`.
```

This is also noted in the
[Rust layout rules](https://doc.rust-lang.org/reference/type-layout.html#the-alignment-modifiers).

This is solved by the article's authors by applying a quite clever layout. Read the article for
(a lot) more details.

# Field order

Another problem is that Rust does not guarantee the order of the different fields.
The [layout rules](https://doc.rust-lang.org/reference/type-layout.html#the-rust-representation)
state that the only guarantees that the Rust representation provides are:

> - The fields are properly aligned.
> - The fields do not overlap.
> - The alignment of the type is at least the maximum alignment of its fields.

This can be easily fixed though by applying the `C` representation with `#[repr(C)]`.

# Fat pointers

Yet another thing to be solved is that [dynamically sized types (DSTs) in Rust](https://doc.rust-lang.org/reference/dynamically-sized-types.html)
require **Fat pointers**. For example, on *x86_64*, pointers normally have a size of `8`, while fat
pointers have a size of `16`. They have to store extra information, such as an array's length or
[a pointer to the vtable](https://doc.rust-lang.org/reference/types/trait-object.html?highlight=vtable)
of the actual type.

```Rust
// u8 arrays of unknown size are DSTs
assert_eq!(16, std::mem::size_of::<Box<[u8]>>());
assert_eq!(16, std::mem::size_of::<&[u8]>());
assert_eq!(16, std::mem::size_of::<*mut [u8]>());

// u8 arrays of known size are not DSTs
assert_eq!(8, std::mem::size_of::<Box<[u8; 42]>>());
assert_eq!(8, std::mem::size_of::<&[u8; 42]>());
assert_eq!(8, std::mem::size_of::<*mut [u8; 42]>());

// references to dyn trait objects are also DSTs
assert_eq!(16, std::mem::size_of::<&dyn std::any::Any>());
```

But this again wastes space, as the length of the String is already stored in the struct. Contained
pointers don't need to have the extra length information.

This is solved by converting in between thin and fat pointers. The following example is a bit
simpler, without a wrapping type:

```Rust
fn fat_to_thin(ptr: *mut [u8]) -> *mut [u8; 0] {
    // fat to thin is easy, just cast
    ptr.cast()
}

fn thin_to_fat(ptr: *mut [u8; 0], len: usize) -> *mut [u8] {
    // thin to fat is a bit trickier, we have to convert to a slice first
    std::ptr::slice_from_raw_parts_mut(ptr.cast(), len)
}
```

# A Sidenote on Phantomdata

Mind the `PhantomData` in one of the structs. When implementing containers with unsafe code, it
is important to remember some of the quirks of the Rust language, especially when handling `*mut`
or `NonNull` pointers.

`PhantomData` is required:

* To allow unused lifetime or type parameters in your generics
* To enforce **Variance** I already wrote another
  [post](@/2024-05-08-an-unsound-cell-implementation.md) about this.
* To enable the [drop check](https://doc.rust-lang.org/std/ops/trait.Drop.html#drop-check) (this is
  subject to change)

See the [PhantomData docs](https://doc.rust-lang.org/std/marker/struct.PhantomData.html) for more
info and examples.
