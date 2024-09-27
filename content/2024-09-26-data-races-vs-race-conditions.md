+++
title = "Data Races vs Race Conditions"
date = 2024-09-26

[taxonomies]
tags = ["data race", "race condition", "threads", "multithreading"]

[extra]
toc = true
+++

I once had an "aha"-moment when realizing the difference between the different terms. I thought it
might be a good idea to write it down for reference.

# Definitions

A **data race** occurs when two or more different threads access the same memory location, where at
least one of them is doing a write.

On the other hand, a **race condition** occurs when the observable outcome of a program is
depending on the timing of how the threads are scheduled.

These definitions clearly look different, but it really made *click* in my head only after I looked
at a few examples.

# A first example

The following example is written in pseudocode.

Consider two threads accessing the same variable `x`:

```C
{
    // Thread 0
    x = 1;
}

// ...

{
    // Thread 1
    x = 2;
}
```

Depending on which thread is executed last, by the end of the program the variable `x` will be set
to either `1` or `2`, so we have a **race condition**. But both threads might also write to the
memory at the same time, which is a **data race**.

Usually you would not notice such a thing (like on *X86_64*), but imagine a software architecture
that does not atomically set the word, but might set the different bits in an arbitrary fashion.
Then one thread might set one bit, while the other sets another bit. We might end up with `0` or
even `3` as a result. This is one of the reasons why data races are considered
**undefined behavior** by several languages such as `C`, `C++` and `Rust`.

# A fix for the Data Race

A common thing to do when confronted with a multithreading problem is to throw mutexes at it. Let's
try this:

```C
{
    // Thread 0
    mutex.lock();
    x = 1;
    mutex.unlock();
}

// ...

{
    // Thread 1
    mutex.lock();
    x = 2;
    mutex.unlock();
}
```

We can easily see now that `x` can only be written to by one thread at a time, so we can't get a
**data race** anymore. But we still have the **race condition**, as the value of the variable still
depends on which thread locks the mutex first.

# A workaround for the race condition

Now there are different ways to fix race conditions, but in this very simple example, we can do
workarounds as ugly as we want, so here we go:

```C
{
    // Thread 0
    x = 1;
}

// ...

{
    // Thread 1
    x = 1;
}
```

Now both threads set `x` to the same value. This has the effect that it does not matter which
thread comes first and which comes last, the variable will in the end always be `1`. So we don't
have a **race condition** anymore.

But note that we again have a **data race**, as it does not matter which value is written.

# Combining both

You probably already guessed it by now - we can avoid both problems by combining both fixes:

```C
{
    // Thread 0
    mutex.lock();
    x = 1;
    mutex.unlock();
}

// ...

{
    // Thread 1
    mutex.lock();
    x = 1;
    mutex.unlock();
}
```

Of course this is not a real-world example, but it shows very nicely the differences of both
problems, and what it comes down to if you want to avoid them.

# Sidenote: Rust

Note that in (safe) Rust, you cannot have **data races**, as the borrow checker does not let you borrow
a mutable reference to `x` while it is already mutably or immutably borrowed. So both threads are
not able to borrow the variable at the same time. You *must* either wrap it in a mutex or solve the issue
differently, e.g. by using atomic data types.

But just because you don't run into **data races** anymore does not mean that you can't have
**race conditions**.
