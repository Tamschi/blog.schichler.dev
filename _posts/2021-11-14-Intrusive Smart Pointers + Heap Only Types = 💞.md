---
title: Intrusive Smart Pointers + Heap Only Types = 💞
date: 2021-11-14 18:44:00 +0100
categories: [Rust]
tags: [patterns, api, walkthrough, crate included]
preview: |-
  A convenient reference-counting optimisation with (now) negative net effort.
pin: true
redirects:
  - /intrusive-smart-pointers-heap-only-types
  - /intrusive-smart-pointers-heap-only-types-ckvzj2thw0caoz2s1gpmi1xm8
image:
  src: /assets/img/posts/2021-11-14-Intrusive Smart Pointers + Heap Only Types = 💞/TauamyRb8.jpg
  width: 1600
  height: 840
  alt: |-
    A Feynman diagram showing how an intrusive `Pin<Arc<Node>>` cloned via `&Node`. The initial `Pin<Arc<Node>>` remains unchanged. An `&Node` is derived from it. As this `&Node` is converted into a full `Pin<Arc<Node>>`, an unlabeled green wavy connector shoots off and mutates the dashed `Node` instance with a slight delay.
---

> In this post:
>
> - Heap only types: Where do they appear?
> - Handling heap only types: `Box`, `Rc` and `Arc`
> - Cloning a handle from a heap-only borrow? (Yes, but…)
> - Can this be more idiomatic? (Yes, if…)
> - Heap-only mutability
> - Intrusive counting
> - How to do this 99% safely? (I made a crate.)
> - The `Clone` hole ⚠
>   - Plugging the `Clone` hole
> - Where to go from here

- - -

> Prior work:
>
> - The initial approach is inspired by [`triomphe::ArcBorrow`](https://docs.rs/triomphe/0.1/triomphe/struct.ArcBorrow.html).

- - -

> Cover image made using <https://feynman.aivazis.com/>.  
> Not physically accurate. Time is horizontal. Lifetime dependencies omitted.

- - -

Please note that this post is a proof of concept. I'm confident it can be implemented in a way that has no or negative overhead compared to, for example, the standard library's smart pointers, but I have not gotten around to do this yet.

## Heap Only Types

Rust can model (at least) two kinds of heap-only-ish types: [Unsized types](https://doc.rust-lang.org/book/ch19-04-advanced-types.html?highlight=Unsized%20Type#dynamically-sized-types-and-the-sized-trait), which cannot be placed on the stack by the compiler because their size is unknown, and **semantically heap-only types**, which are contextually heap-only whenever an API doesn't allow them to be observable elsewhere.
As usual, these limitations don't exist for `unsafe` Rust, which is beyond the scope of this post.

The type examined here is only semantically heap-only towards a consumer in a different crate, but the pattern I present also works for unsized (dynamically-sized) types.

### Where do they appear?

There is an opportunity to make a type heap-only whenever it would otherwise be useless. A good example is the following reference-counted inverse tree:

```rust
// ances-tree/lib.rs
use std::{borrow::Borrow, sync::Arc};
use tap::Pipe; // ¹

#[cfg(doctest)]
pub mod readme {
	doc_comment::doctest!("../README.md");
}

/// A reference-counting inverse tree node.
#[derive(Debug, Clone)]
pub struct Node<T> {
	pub parent: Option<Arc<Self>>,
	pub value: T,
}

impl<T> Node<T> {
	/// Creates a new [`Node`] instance with the given `parent` and `value`.
	pub fn new(parent: Option<Arc<Self>>, value: T) -> Self {
		Self { parent, value }
	}

	/// Retrieves a reference to a [`Node`] with a value matching `key` iff available.
	///
	/// See also: <https://doc.rust-lang.org/stable/std/collections/hash_set/struct.HashSet.html#method.get>
	#[must_use]
	pub fn get<Q: ?Sized>(&self, key: &Q) -> Option<&Self>
	where
		T: Borrow<Q>,
		Q: Eq,
	{
		let mut this = self;
		while this.value.borrow() != key {
			this = this.parent.as_ref()?
		}
		Some(this)
	}

	// Abridged. See omitted code at ².
}
```

¹ Not shown in this abridged snippet, I'm using myrrlyn's excellent [tap](https://crates.io/crates/tap) crate to organise long expressions in execution order.  
² [Tamschi/ances-tree 🔖blog-link/basic-inverse-tree (lib.rs#L46-L124)](https://github.com/Tamschi/ances-tree/blob/blog-link/basic-inverse-tree/src/lib.rs#L46-L124)

💁‍♂️ *I've published this example crate on GitHub and will occasionally link tags and diffs for you to follow along. The project that inspired this pattern, [rhizome](https://github.com/Tamschi/rhizome#readme), is too verbose and messy to cite here, but follows generally the same structure.*  
*You can see the changes for each section in this post in [the blog-steps branch](https://github.com/Tamschi/ances-tree/commits/blog-steps). GitHub isn't too clear about this, but the section title ones are merge commits that together contain all changes.*

Note that the above doesn't make `Node` heap-only yet!

## Handling heap only types

To restrict a type to the heap, we [pin](https://doc.rust-lang.org/stable/core/pin/index.html) it behind a smart pointer (in this case [`Arc`](https://doc.rust-lang.org/stable/alloc/sync/struct.Arc.html)) as follows:

```rust
use std::{borrow::Borrow, marker::PhantomPinned, pin::Pin, sync::Arc};
use tap::Pipe;

/// A reference-counting inverse tree node.
#[derive(Debug)] // No `Clone`!
pub struct Node<T> {
	pub parent: Option<Pin<Arc<Self>>>,
	pub value: T,
	// The private field also prevents construction elsewhere.
	_pin: PhantomPinned,
}

impl<T> Node<T> {
	/// Creates a new [`Node`] instance with the given `parent` and `value`.
	pub fn new(parent: Option<Pin<Arc<Self>>>, value: T) -> Pin<Arc<Self>> {
		Self {
			parent,
			value,
			_pin: PhantomPinned,
		}
		.pipe(Arc::pin)
	}

	// `.get(…)` unchanged.
	// `.get_mut(…)` and `.make_mut(…)` removed for now.
}
```

The consumer now never sees a `Node` or `&mut Node` directly, which means the instances can't be moved away from the heap.

The `.get(…)` method remains unchanged as `&Node` is still accessible through [`impl<P: Deref> Deref for Pin<P>`](https://doc.rust-lang.org/stable/core/pin/struct.Pin.html#impl-Deref).

`.get_mut(…)` and `.make_mut(…)` have been removed for now since the Rust standard library doesn't provide equivalents of *its* [`Arc::get_mut`](https://doc.rust-lang.org/stable/alloc/sync/struct.Arc.html#method.get_mut) and [`Arc::make_mut`](https://doc.rust-lang.org/stable/alloc/sync/struct.Arc.html#method.make_mut) functions for `Pin<Arc<…>>`.  
Note that even exclusively held `Node`'s are effectively read-only now. There are work-arounds for all of this, of course, but they involve a lot of `unsafe`. This feature will safely come back later on, though.

## Cloning a handle from a heap-only borrow?

When borrowing the contents of an `Arc<T>`, we usually want to handle a `&T` rather than an `&Arc<T>` to avoid a double-indirection when accessing the value.

Since any API consumer will only see pinned `Node`s, we *know* that any `&Node` we see actually points to an instance managed by `Arc`. Can we increment the reference count to create an additional `Arc`?

The answer is, unfortunately here but fortunately in general, no.

Even if `Arc` had a known layout with a known pointer offset, we would not be allowed to magic-up a borrow using pointer maths:  
As the `Arc` reference count is stored outside `Node`, we must not* access it through `&Node` even using pointer maths, as this would be an out-of-bounds read.

💁‍♂️ \*Technically *code like that works right now, but I'm told it's still considered UB. Never allowing out-of-bounds access through references could enable or at least simplify powerful optimisations in the future.*

As `triomphe` has a matching known-`Arc`-borrow API, we can quickly see what this *would* look like if we borrowed into a pointer and abstracted instead.

First, we switch out the `Arc` import:

```rust
use std::{borrow::Borrow, marker::PhantomPinned, pin::Pin};
use tap::Pipe;
use triomphe::{Arc, ArcBorrow};
```

and adjust the constructor a bit since `triomphe` isn't `Pin`-aware:

```rust
impl<T> Node<T> {
	/// Creates a new [`Node`] instance with the given `parent` and `value`.
	pub fn new(parent: Option<Pin<Arc<Self>>>, value: T) -> Pin<Arc<Self>> {
		Self {
			parent,
			value,
			_pin: PhantomPinned,
		}
		.pipe(Arc::new)
		.pipe(|arc| unsafe { Pin::new_unchecked(arc) })
	}

	// `.get(…)` unchanged.
	// `.get_mut(…)` and `.make_mut(…)` still missing.
}
```

We also have to shim the following functions:

```rust
#[must_use]
pub fn borrow<T>(this: &Pin<Arc<Node<T>>>) -> Pin<ArcBorrow<'_, Node<T>>> {
	unsafe { &*(this as *const Pin<Arc<Node<T>>>).cast::<Arc<Node<T>>>() }
		.pipe(Arc::borrow_arc)
		.pipe(|arc_borrow| unsafe { Pin::new_unchecked(arc_borrow) })
}

#[must_use]
pub fn clone_arc<T>(this: &Pin<ArcBorrow<Node<T>>>) -> Pin<Arc<Node<T>>> {
	unsafe { &*(this as *const Pin<ArcBorrow<Node<T>>>).cast::<ArcBorrow<Node<T>>>() }
		.pipe(ArcBorrow::clone_arc)
		.pipe(|arc| unsafe { Pin::new_unchecked(arc) })
}
```

So far so good.

Their signatures are a mouthful, so we'll change the code again to abstract the borrow type a bit, and use that abstraction everywhere it's applicable.

First the borrow:

```rust
#[derive(Debug)]
pub struct NodeBorrow<'a, T> {
	arc_borrow: Pin<ArcBorrow<'a, Node<T>>>,
}

impl<T> Deref for NodeBorrow<'_, T> {
	type Target = Node<T>;

	fn deref(&self) -> &Self::Target {
		&*self.arc_borrow
	}
}
```

And then the handle:

```rust
#[derive(Debug)]
pub struct NodeHandle<T> {
	arc: Pin<Arc<Node<T>>>,
}

impl<T> NodeHandle<T> {
	/// Creates a new [`Node`] instance with the given `parent` and `value`.
	pub fn new(parent: Option<NodeHandle<T>>, value: T) -> Self {
		Node {
			parent,
			value,
			_pin: PhantomPinned,
		}
		.pipe(Arc::new)
		.pipe(|arc| unsafe { Pin::new_unchecked(arc) })
		.pipe(|arc| Self { arc })
	}

	#[must_use]
	pub fn borrow(this: &Self) -> NodeBorrow<'_, T> {
		unsafe { &*(&this.arc as *const Pin<Arc<Node<T>>>).cast::<Arc<Node<T>>>() }
			.pipe(Arc::borrow_arc)
			.pipe(|arc_borrow| unsafe { Pin::new_unchecked(arc_borrow) })
			.pipe(|arc_borrow| NodeBorrow { arc_borrow })
	}

	#[must_use]
	pub fn clone_handle(this: &NodeBorrow<T>) -> Self {
		unsafe {
			&*(&this.arc_borrow as *const Pin<ArcBorrow<Node<T>>>).cast::<ArcBorrow<Node<T>>>()
		}
		.pipe(ArcBorrow::clone_arc)
		.pipe(|arc| unsafe { Pin::new_unchecked(arc) })
		.pipe(|arc| Self { arc })
	}
}

impl<T> Deref for NodeHandle<T> {
	type Target = Node<T>;

	fn deref(&self) -> &Self::Target {
		&*self.arc
	}
}
```

`Node` itself loses its constructor and now stores a `NodeHandle` as parent reference:

```rust

/// A reference-counting inverse tree node.
#[derive(Debug)]
pub struct Node<T> {
	pub parent: Option<NodeHandle<T>>,
	pub value: T,
	_pin: PhantomPinned,
}

impl<T> Node<T> {
	// Constructor removed, otherwise unchanged.
}
```

That's fairly nice now. The only sticking points are that we have a `NodeBorrow<'a, T>` instead of an `&'a Node` and no exclusive/mutable references to `Node`.

Exposing two bespoke helper types to fix clumsy signatures also isn't ideal, but more of an incidental issue.

## Can this be more idiomatic?

Let's say we had a hypothetical `Arc<T>` that was legal to borrow from `&T`. Let's also say it was pinning-aware so that we can skip some boilerplate while preventing any de-boxing.

First, our `NodeHandle` is now a type alias, since we won't need additional functions:

```rust
pub type NodeHandle<T> = Pin<Arc<Node<T>>>;
```

Second,

```rust
pub type NodeBorrow<'a, T> = &'a Node<T>;
```

, but since that type alias is longer than its original type, we'll just write `&Node<T>` instead.

Third, `Node` remains unchanged for now, but all functions are concentrated on that type like this:

```rust
impl<T> Node<T> {
	/// Creates a new [`Node`] instance with the given `parent` and `value`.
	pub fn new(parent: Option<NodeHandle<T>>, value: T) -> NodeHandle<T> {
		Node {
			parent,
			value,
			_pin: PhantomPinned,
		}
		.pipe(Arc::pin)
	}

	/// Retrieves a reference to a [`Node`] with a value matching `key` iff available.
	///
	/// See also: <https://doc.rust-lang.org/stable/std/collections/hash_set/struct.HashSet.html#method.get>
	#[must_use]
	pub fn get<Q: ?Sized>(&self, key: &Q) -> Option<&Self>
	where
		T: Borrow<Q>,
		Q: Eq,
	{
		let mut this = self;
		while this.value.borrow() != key {
			this = this.parent.as_ref()?
		}
		Some(this)
	}

	#[must_use]
	pub fn clone_handle(&self) -> NodeHandle<T> {
		todo!() // 🤔
	}

	// Mutability will be back, eventually.
}
```

The `Arc` can't know that our `Node` is only ever visible behind `Arc`, so we have to provide a safe `.clone_handle()` method ourselves.

## Heap-only mutability

The signature of an exclusive borrow in Rust is `Pin<&mut _>`. While the `Arc` can't be `DerefMut` (which would allow us to use [`Pin::as_mut`](https://doc.rust-lang.org/stable/std/pin/struct.Pin.html#method.as_mut)), it can generically provide us with pinning alternatives to its `get_mut` and `make_mut` methods.

We can use these to go from `&mut NodeHandle<T>` to `Pin<&mut Node<T>>`.

💁‍♂️  *`Pin<&mut Node<T>>` is `Deref<Target = Node<T>>` (because `&mut Node<T>` is the same), so we could access a shared reference and clone the `NodeHandle<T>`, which would give us a parallel shared reference to our now-free-again exclusive reference (`&Node<T>` and parallel `&mut Node<T>`). This would be [extremely bad](https://doc.rust-lang.org/reference/behavior-considered-undefined.html).*

*We'll assume that the `Arc` already protects against this invalid construct, at the cost of slight (additional) overhead per exclusive borrow.*

This isn't quite enough to let a consumer change the contents of the instance, since we still aren't providing mutable access to the public fields. Manual pin-projection is somewhat error-prone to implement, so we're going to let the [pin-project](https://crates.io/crates/pin-project) crate take care of that:

```rust
/// A reference-counting inverse tree node.
#[pin_project::pin_project]
#[derive(Debug)]
pub struct Node<T> {
	pub parent: Option<NodeHandle<T>>,
	pub value: T,
	#[pin] // Required to keep `Node<T>: !Unpin`!
	_pin: PhantomPinned,
}

impl<T> Node<T> {
	#[must_use]
	pub fn parent_mut<'a>(self: &'a mut Pin<&mut Self>) -> &'a mut Option<NodeHandle<T>> {
		self.as_mut().project().parent
	}

	#[must_use]
	pub fn value_mut<'a>(self: &'a mut Pin<&mut Self>) -> &'a mut T {
		self.as_mut().project().value
	}
}
```

We must mark `_pin` as structural(ly pinned) here; otherwise `pin_project` would `impl<T> Unpin for Node<T> {}` with no constraints.

The `self: &'a mut Pin<&mut Self>` parameter on these methods looks a bit strange, but lets a consumer call them directly on the guard we get from `Arc::get_mut`:

```rust
#[test]
fn test() {
	let mut handle = Node::new(None, 1);
	{
		let mut exclusive = Arc::get_mut(&mut handle).unwrap();
		let _: &mut i32 = exclusive.value_mut();
		let _: &mut Option<NodeHandle<i32>> = exclusive.parent_mut();
	}

	let second_handle = Pin::clone(&handle);
	assert!(Arc::get_mut(&mut handle).is_none());
	assert_eq!(second_handle.value, 1);
}
```

💁‍♂️  *It's likely a good idea to inline `parent_mut` and `value_mut`. However, performance-optimisation is arbitrarily out of scope for this post.*

## Intrusive counting

The reason `alloc::sync::Arc` and `triomphe::Arc` can't quite soundly go from "`&T`-behind-`Arc<T>`" to a cloned `Arc<T>` is *only* the required out-of-bounds access to the `Arc`'s reference counter in those case.

If we can move the reference-counter *inside* the contained instance, we are then able to get a reference to it and, by effectively reimplementing `alloc::sync::Arc<T>` **without exposing `&mut T`**, can arrive at the API above.

At this point, only the following types are exposed:

- A generic `Arc<T>` that acts much like the standard library's.
- A generic guard that ensures mutable borrow exclusivity dynamically.
- Our `Node<T>`, which contains the entirety of our API.

## How to do this (almost) safely?

The necessary smart pointer I needed for the above turned out to be really easy to abstract, so I've turned it into a crate that you can find here: [📦tiptoe](https://crates.io/crates/tiptoe)

(Be sure to activate the `"sync"` feature to use `Arc`.)

You still have to adjust your `struct` to make it compatible, but this can be done in few lines of code and without using `unsafe` more than once:

```rust
use std::{borrow::Borrow, pin::Pin};
use tap::Pipe;
use tiptoe::{Arc, IntrusivelyCountable, TipToe};

/// A reference-counting inverse tree node.
#[pin_project::pin_project]
#[derive(Debug)]
pub struct Node<T> {
	pub parent: Option<NodeHandle<T>>,
	pub value: T,
	#[pin] // Required to keep `Node<T>: !Unpin`!
	tip_toe: TipToe,
}

impl<T> Node<T> {
	/// Creates a new [`Node`] instance with the given `parent` and `value`.
	pub fn new(parent: Option<NodeHandle<T>>, value: T) -> NodeHandle<T> {
		Node {
			parent,
			value,
			tip_toe: TipToe::new(),
		}
		.pipe(Arc::pin)
	}
}

unsafe impl<T> IntrusivelyCountable for Node<T> {
	type RefCounter = TipToe;

	#[inline(always)]
	fn ref_counter(&self) -> &Self::RefCounter {
		&self.tip_toe
	}
}
```

`TipToe`, the reference-counting slot, is written to be as unobtrusive as possible:

- It's transparent to all standard comparisons and hashing.
- It implements `Default` and `Clone` (but the clone always has the default value).
- It's `!Unpin`, so it can be used to pin the surrounding struct.

`tiptoe::Arc<T>` will never provide a `&mut` reference to its contents directly (and provides `Pin<&mut _>` only as `Pin<Arc<_>>`), but if `T: Unpin`, then `Arc<T>` and `Pin<Arc<T>>`, and `Pin<&mut T>` and `&mut T`, are equivalent and can be converted safely. Keep this in mind when exposing instances of your types through a conversion that requires `unsafe`.

`TipToed`, the trait by which `Arc` finds the intrusive counter, is unsafe as Rust's type system can't guarantee a "boring" implementation with only one embedded counter returned at all times. (The actual safety requirements are actually slightly more lenient than that, though. The true requirement is that it mustn't confuse the count in a way that would cause instances to be dropped early, and that the call must have absolutely no (observable) effect.)

Since `Node` is a heap-only *and `Arc`-only* type via pinning, we can additionally provide the following method:

```rust
impl<T> Node<T> {
	#[must_use]
	pub fn clone_handle(&self) -> NodeHandle<T> {
		Pin::clone(unsafe { Arc::borrow_pin_from_inner_ref(&self) })
	}
}
```

As you can see, we assume `&self` is behind a `Pin<Arc<_>>`. `Arc<_>` is ABI-compatible with a plain shared reference, so it can be borrowed from one (via a short detour through `&&self`).

## The `Clone` hole ⚠

`tiptoe::Arc` also provides a `make_mut` function, which has the same copy-on-write functionality as in the standard library. However, there is a problem with making this available for our `Node<T>`: `alloc::sync::Arc::<T>::make_mut` requires `T: Clone`.

We cannot implement `Clone` on `Node<_>` because that would allow a consumer to move from `&Node<T>` to `Node<T>`, an instance decidedly off-heap.

### Plugging the `Clone` hole

For this reason, `tiptoe::Arc::<T>::make_mut` instead requires `tiptoe::ManagedClone`. This trait has the same shape as `Clone` but its methods are `unsafe` and it comes with a caller restriction:

```rust
/// # Safety
///
/// This method may only be used to create equally encapsulated instances.
///
/// For example, if you can see the instance is inside a [`Box`](`alloc::boxed::Box`),
/// then you may clone it into another [`Box`](`alloc::boxed::Box`) this way.
///
/// If you have only a reference or pointer to the implementing type's instance,
/// but don't know or can't replicate its precise encapsulation, then you must not call this method.
///
/// You may not use it in any way that could have side-effects before encapsulating the clone.
/// This also means you may not drop the clone. Forgetting it is fine.
unsafe fn managed_clone(&self) -> Self;
```

In short: This method mustn't be used by an API consumer to interact with unwrapped instances.

(Any type that is `Clone` is automatically `ManagedClone`.)

You can find this final step in the implementation here:
[Tamschi/ances-tree 🔖blog-link/managed-clone (lib.rs#L83-L94)](https://github.com/Tamschi/ances-tree/blob/blog-link/managed-clone/src/lib.rs#L83-L94)  
The *develop* branch also contains a rehash of the assumptions made at each location where `unsafe` is used.

## Where to go from here

I've implemented tiptoe only as far as I personally need it, so there are a few open points where it could be more useful:

- Nobody has audited `tiptoe` so far. It contains a lot of `unsafe` snippets, so getting a few more eyes on it would be helpful in this regard.

- I currently only need `Arc`, not `Rc`. I've implemented `TipToe` in such a way that it can alternatively act as `Rc` reference counter with no synchronisation overhead, so it should be fairly easy to copy-paste the latter from the former if needed.

- The crate is unoptimised in terms of speed. I don't have experience with benchmarking Rust and don't need the crate to be particularly fast right now.

- `TipToe` is a strong reference counter only. From what I can tell, `tiptoe::Arc` and an eventual `tiptoe::Rc` could become compatible with an additional intrusive strong/weak counter without breaking API changes.

- I may add an `ExclusiveArc<_>` or `Unique<_>` type in the future, which would behave like a standard `Box<_>` but set the internal counter to the exclusivity value until converted into an `Arc`. It's also likely possible to improve the way dynamic exclusivity works, but I suspect I currently lack the necessary skills for that.
