## Semantic FFI Bindings in Rust -
Reactivating the Borrow Checker

> In this post:
> - Rust references, opaque handles and ownership
> - Likely pitfalls or: `c_void` isn't (yet) C's `void`
> - One big caveat
> - Lifetime-generic opaque references and callbacks
- - -
> - Prerequisites:  
>   The Rustonomicon's pages on [How Safe and Unsafe Interact](https://doc.rust-lang.org/nomicon/safe-unsafe-meaning.html) and on [FFI](https://doc.rust-lang.org/nomicon/ffi.html)  
> - Optional reading:  
>   [cppreference.com on the `restrict` type qualifier](https://en.cppreference.com/w/c/language/restrict)
- - -

🎨 *The image displayed on my watch is unsafe!Ferris by @&zwj;whoisaldeka on Twitter, first posted [here](https://twitter.com/whoisaldeka/status/674465785557860353) under CC-BY... though *technically* speaking I downscaled the SVG version that's in the Rustonomicon.*

I recently succeeded at writing a watch app for my old Kickstarter Pebble and made some discoveries in the process that may be interesting to others working on similar projects or FFI bindings in general. This post is part one of a two-part series, with the other (planned to be) covering some tricks you can use when wrapping an OOP C API.

<!-- TODO: Change this back to "`nightly-2020-10-31` (🎃&zwj;boo!)" once available. -->
💁‍♂️ *Some of the advice in this post hinges on the e.g. `nightly-2020-10-30` `#![feature(extern_types)]`. To my knowledge, there is currently no fully sound way to use fully opaque references on stable!  
Should the feature change, please ping me with a comment and I'll update this post accordingly.*

A good starting point when writing FFI bindings is to transliterate the original C headers as closely as possible. For example's sake, we'll examine a few functions from [this page](https://developer.rebble.io/developer.pebble.com/docs/c/User_Interface/Window/index.html) of the Pebble SDK docs:

```c
// C
typedef struct Layer Layer;
typedef struct Window Window;

Window * window_create(void);
bool window_is_loaded(Window * window);
window_set_background_color(Window * window, GColor background_color);
struct Layer * window_get_root_layer(const Window * window);
void window_destroy(Window * window);
``` 
becomes
```rust
extern "C" {
  type Layer; // Nightly feature: extern_types
  type Window;

  fn window_create() -> *mut Window;
  fn window_is_loaded(window: *mut Window) -> bool;
  fn window_set_background_color(window: *mut Window, background_color: GColor);
  fn window_get_root_layer(window: *const Window) -> *mut Layer;
  fn window_destroy(window: *mut Window);
}
```

[Extern types](https://github.com/rust-lang/rust/issues/43467) have a few useful properties, like not implementing *any* of the auto-traits by default. They are considered fully thread-unsafe and panic-unsafe, unless you explicitly specify otherwise. We're dealing with a watch that doesn't support threading at all, and also doesn't know exceptions beyond bailing from a faulty app, so for the most part we'll ignore this aspect.

A more interesting, and unique, property is that references (`&` and `&mut`) to extern types are FFI-safe as slim pointers while the type itself is considered unsized.  
Rust normally really likes to reorganise the backing storage of references: Small values passed by reference can be "inlined" and passed by value instead, if that produces faster or smaller code. Even data behind a mutable reference can be copied and later written back due to [Rust's strict aliasing rules](https://doc.rust-lang.org/nomicon/aliasing.html). However, if the size of the data isn't known, it *can't:*

### Rust preserves pointer identity of references to extern types!

That's it, that's the post.

⋮

No, not really. There are a few finer points to take care of here. You may have noticed that I didn't cite any of the non-code documentation. (Examples aren't necessary exact copies from here on out.)

```c
/* Creates a new Window on the heap and initializes it with the default values.
 * [information about default values]
 *
 * RETURNS:
 *   A pointer to the window.
 *   `NULL` if the window could not be created.
 */
Window * window_create(void);

/* Destroys a Window previously created by window_create.
*/
void window_destroy(Window * window);
```

Hm... So this window creation function is actually fallible, but `window_destroy` expects a valid Window handle 🤔  
We couldn't tell from the signature alone because in C, all pointers are nullable. The developers would have had to compromise on convenience and/or write unidiomatic code to avoid this. That `window_create` can fail but `window_destroy` expects an actual instance makes sense too: This API is the same across all watch generations that were made, which includes my "aplite" with only 100kB RAM in total, and only 24kB for app executable and heap combined. Creating too many Windows **will** fail eventually.  
Apps will usually configure their windows, so it's more efficient to assume they will branch once after creation than making every other function accept null pointers. On a low power device, that's a sensible design in my opinion.

In any case, the first binding above lets us write the following unsound code without a complaint from the compiler:

```rust
unsafe { window_destroy(window_create()) } // No!!!
```

That's a [segfault](https://en.wikipedia.org/wiki/Segmentation_fault#Null_pointer_dereference) in the making.

Can we do better? In stable Rust, the answer is "somewhat":

```rust
struct Layer([u8; 0]); // Extern types aren't stable as of 2020-10-31.
struct Window([u8; 0]);

extern "C" {
  fn window_create() -> Option<NonNull<Window>>;
  fn window_is_loaded(window: NonNull<Window>) -> bool;
  fn window_set_background_color(window: NonNull<Window>, background_color: GColor);
  fn window_get_root_layer(window: NonNull<Window>) -> NonNull<Layer>;
  fn window_destroy(window: NonNull<Window>);

  /// Destroys a layer previously created by layer_create.
  fn layer_destroy(window: NonNull<Layer>);
}
```

It's a bit awkward, but [`NonNull`](https://doc.rust-lang.org/stable/core/ptr/struct.NonNull.html) is FFI-safe and tells us precisely when the pointer points to actual memory.
We lost the `const` qualifier on `window_get_root_layer`'s argument, but that's an okay tradeoff to avoid a hard-to-debug segfault.

We can now use the bindings like this:

```rust
unsafe {
  let window = window_create().unwrap(); // Not elegant, but panics do create a trace!
  window_set_background_color(window, GREEN);
  let layer = window_get_root_layer(window);
  // …
  if !window_is_loaded(window) {
    window_destroy(window);
  }
  // …
  window_destroy(window); // Oh.
  layer_destroy(layer); // Oh no!
}
```

That's one conditional double free and one API contract violation 🙁  
(This `layer` wasn't "created by layer_create". We got it from the Window instance which presumably dismantles it on destruction.)

Can we do better? Not on stable. Our opaque newtypes above are zero-sized, so their address would likely be erased when handling references to them. Similarly the core type [`c_void`](https://doc.rust-lang.org/stable/core/ffi/enum.c_void.html) is, as of Rust 1.47.0, implemented as

```rust
#[repr(u8)]
#[stable(feature = "core_c_void", since = "1.30.0")]
pub enum c_void {
    #[unstable(
        feature = "c_void_variant",
        reason = "temporary implementation detail",
        issue = "none"
    )]
    #[doc(hidden)]
    __variant1,
    #[unstable(
        feature = "c_void_variant",
        reason = "temporary implementation detail",
        issue = "none"
    )]
    #[doc(hidden)]
    __variant2,
}
```

That's not unsized. It's actually quite a bit smaller than a usual reference too, so the compiler will most likely shift this memory around a lot if we create a `&` or `&mut` reference to this type!

💁‍♂️ *[But even creating the Rust references would be undefined behaviour already](https://doc.rust-lang.org/nomicon/what-unsafe-does.html), if we use it as stand-in for opaque C types: We can't be sure that the memory location contains a valid discriminant for this enum (or, for that matter, *exists at all*, but that's secondary here). Creating a Rust reference to a (potentially) invalid value is immediately unsound, even without dereferencing it!*

### There is a better way (coming)

As mentioned before, it is safe to create references to extern types regardless of their underlying data (though the API in question may limit this). With this in mind, we can rewrite our FFI bindings with full (shortened) documentation like this:

💁‍♂️ _**There is one important caveat to this.** I'll get to it later, and it's a bit of a nasty footgun, so please bear with me._

```rust
extern "C" {
  type Layer; // Nightly feature: extern_types
  type Window;

  /// [information about default values]
  fn window_create() -> Option<&'static mut Window>;

  /// True if between `load` and `unload` callbacks.
  fn window_is_loaded(window: &mut Window) -> bool;

  /// This color is drawn by the window's root [`Layer`].
  fn window_set_background_color(window: &mut Window, background_color: GColor);

  /// [information about layer layering]
  fn window_get_root_layer(window: &Window) -> &mut Layer;

  /// Destroys a [`Window`] previously created by [`window_create`].
  fn window_destroy(window: &'static mut Window);

  /// Destroys a [`Layer`] previously created by [`layer_create`].
  fn layer_destroy(window: &'static mut Layer);
}
```

That's short! The functions' signatures say a lot about how to call them already, so there was room to add other information undisturbed.

Something a bit peculiar is how commonly `&'static mut ExternType` appears, which is pretty unidiomatic in regular Rust. I think the best way to describe these references is as "exclusive handle": There are no storage limitations on them, so you can move them across the heap without problem, but once you pass them into a function (like the destructors here), they are gone.

Let's try the previous usage example again:

```rust
unsafe {
  let window = window_create().unwrap(); // Not elegant, but panics do create a trace!
  window_set_background_color(window, GREEN);
  let layer = window_get_root_layer(window);
  // …
  if !window_is_loaded(window) {
    window_destroy(window);
  }
  // …

  // Doesn't compile:
  //   cannot borrow `*window` as mutable more than once at a time
  window_destroy(window);

  // Causes issues above:
  //   cannot borrow `*window` as mutable because it is also borrowed
  //   as immutable
  layer_destroy(layer);
}
```

Great! Note that this isn't perfect - we could for example destroy the root layer if we leak the window, which could be prevented with likely zero runtime cost with additional `#[repr(transparent)]` newtype wrappers and proxy functions - but for concise FFI bindings this is a seriously low footgun density.

💁‍♂️ *This is still an unsafe API in other respects. For example, the window stack API gives out long-lived window handles that collide with handles we already hold, and there are some places where valid parameters are limited in a way Rust's type system can't represent directly.*

### The Caveat

There is one really important rule to keep in mind when designing FFI bindings like this: **[A mutable reference cannot be aliased](https://doc.rust-lang.org/nomicon/references.html)**. Doing so is immediately undefined behaviour.

On a safe API, this generally isn't a problem: There would be either exactly one location to acquire an exclusive handle like this, or wrapper types that drop the restriction internally. (We can't quite do this in a pure FFI binding, because the type in question would have to follow borrow semantics while implementing [`Copy`](https://doc.rust-lang.org/stable/core/marker/trait.Copy.html) to be passed as value.)

Here's an example:

```rust
// This is a misleading binding!
extern "C" {
  fn window_create() -> Option<&'static mut Window>;
  fn window_stack_push(window: &mut Window, animated: bool);
  fn window_stack_pop(animated: bool) -> Option<NonNull<Window>>;
}

unsafe {
  let window = window_create()?;
  window_stack_push(window, true);
  // …
  let popped = window_stack_pop(true)?;
  // …
  window_stack_push(&mut *popped, true); // Whoops.
}
```

In the last line, `window` and the temporary mutable reference `&mut *popped` are aliased. Most importantly, this was low friction on the consumer's part, too. Not&nbsp;good!

What went wrong? The issue here is that `window_stack_push` sets us up for retrieving the window handle later, but doesn't take exclusive ownership of it. In C this makes sense: No part of the API is marked `restrict`, the handle stays valid after this API call and manipulating it afterwards is a common pattern.

Rust isn't so lenient, so let's fix the extern declarations for our purposes:

```rust
extern "C" {
  fn window_create() -> Option<&'static mut Window>;
  fn window_stack_push(window: &'static /* ← */ mut Window, animated: bool);
  fn window_stack_pop(animated: bool) -> Option<NonNull<Window>>;
}

unsafe {
  let window = window_create()?;
  window_stack_push(window, true);
  // …
  let popped = window_stack_pop(true)?;
  // …
  window_stack_push(&mut *popped, true); // Sound!
}
```

Barely anything changed, but… suddenly the program is well-formed?

The reason for this is that `popped` is now directly derived from the `window` borrow, without releasing it in the meantime. Parallel aliased `&mut` references are UB, but they are also nestable and reentrant**¹**, which means the code above checks out.

💁‍♂️ *A high level wrapper will probably want to reorganise the API so that it holds onto a `Window` reference independently of threading it through the C callback API mentioned further below. This can be done by downgrading it to a pointer while at rest, combined with careful (safe) API surface restrictions, but the details of that are material for another post.*

### Lifetime-generic opaque references

In the Pebble API, certain instances reference external data. Unfortunately, extern types don't support generics directly, so

```rust
extern "C" {
  pub type NumberWindow<'a>;
}
```

does not compile.

💁‍♂️ *Visibilities didn't matter much before this, so I left them out to reduce noise. I'll include them from here on out.*

Instead, the way we can model the API correctly is as follows:

```rust
#[repr(transparent)]
pub struct NumberWindow<'a>(PhantomData<&'a ()>, ExternData);

extern "C" {
  type ExternData;
  type CStr;
  pub type void; // Actually like C's `void`.

  pub fn number_window_create<'a>(
    label: &'a CStr, // Can be changed later.
    callbacks: NumberWindowCallbacks,
    callback_context: &'a mut void,
  ) -> Option<&'a mut NumberWindow<'a>>;

  pub fn number_window_destroy(number_window: &'static mut NumberWindow);
}
```

`NumberWindow` inherits properties from both [`PhantomData`](https://doc.rust-lang.org/nomicon/phantom-data.html) (here a variant lifetime, but no accessible data) and `ExternData` (unsized with slim pointer). It's a newtype that behaves as "limited-lifetime&nbsp;foreign&nbsp;type".

💁‍♂️ *`NumberWindow` sports a user data pointer (`callback_context` above) on the C side, and I'd very much like to expose that in a strongly typesafe way too. Making `NumberWindow` itself generic over a type isn't a problem because of `PhantomData`, but the following is unfortunately not legal in Rust:*

```rust
extern "C" {
  fn function<T>(); // E0044: foreign items may not have type parameters
}
```

Something to note is that `number_window_destroy` still takes an indefinite exclusive borrow (`&'static mut`). This parameter can't be relaxed more without making unsound usage convenient.

The `NumberWindow` here is still `NumberWindow<'_>`, but Rust doesn't actually allow a `&'static NumberWindow<'_>` to exist, so the consumer has to use a slightly longer pointer cast (`&mut *(number_window as *mut _ as *mut void as *mut _)`) to destroy it. If you have a better idea for how to bind this (in context!), I'm all ears.

### Lifetime-generic callbacks

There is one final point I'd like to cover, which is the interaction of generic foreign types and function pointer types. [On the C side](https://developer.rebble.io/developer.pebble.com/docs/c/User_Interface/Window/NumberWindow/index.html), the following definition exists:

```c
typedef void(* NumberWindowCallback)(
  struct NumberWindow *number_window,
  void *context
);
```

C's function pointer type definitions aren't all that easy to read, but here's a compatible Rust function that matches our earlier FFI declarations:

```rust
extern "C" fn example_handler<'a>(
  number_window: &'a mut NumberWindow<'a>,
  context: &mut void,
) {
  // This is a concrete implementation.
}
```

The function has a generic parameter, so to declare the matching pointer type we can either use a concrete lifetime and thread that through the container hierarchy a bit or, more conveniently and accurately, we can use a [type alias](https://doc.rust-lang.org/stable/reference/items/type-aliases.html) to a polymorphic function pointer type:

```rust
pub type NumberWindowCallback =
  for<'a> extern "C" fn(
    number_window: &'a mut NumberWindow<'a>,
    context: &mut void,
  );
```

💁‍♂️ *Rust's documentation doesn't quite spell out that this is possible for plain function pointers in addition [to traits](https://doc.rust-lang.org/stable/reference/trait-bounds.html#higher-ranked-trait-bounds), or what to call it. The one specific mention I found after digging for a bit is the `ForLifetimes?` in the formal grammar on [function pointer types](https://doc.rust-lang.org/stable/reference/types/function-pointer.html), which just links to the section on where clauses.*

(Thanks for the correction, @[Mazdak Farrokhzad](@centril)!)

### What's next

I hope this post has been helpful so far. [`pebble-sys`](https://github.com/Tamschi/pebble-sys#pebble-sys) is still a work in progress, but I believe it's on a good trajectory and this is just about everything I learned while working on it so far. It's actually my first FFI binding (not counting C#), but it's fun to go a bit beyond transliterating the C declarations 😅

For the next post, I want to cover the constructs I used to reconcile Pebble's polymorphic OOP API, memory safety, and 24kB of app working memory in [`pebble-skip`](https://github.com/Tamschi/pebble-skip#pebble-skip). You'll also see a custom *fallible* [`Box`](https://doc.rust-lang.org/stable/std/) with direct unsizing coercions.

- - -

¹ Full disclosure: I was unable to find a direct mention of this latter bit. However, without reentrant mutable references, available pointer arithmetic would essentially be nonsensical, so I'm *pretty sure* re-entering mutable references from pointers is legal. It would be good to have some clarification here.