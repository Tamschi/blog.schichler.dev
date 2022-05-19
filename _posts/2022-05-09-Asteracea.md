---
title: Asteracea (as of right now) 🌼
date: 2022-05-14 15:25:00 +0200
categories: [Rust, Asteracea]
tags: [web, frontend, components, DSL]
preview: |-
  A bird's-eye view of Asteracea, my frontend framework.  
  Topics include semantic locality, efficient stateful and stateless components, named parameters, efficient VDOM double-buffering with drop-notifications, ….
pin: true
---

This is a relatively high-level summary post of design decisions I made so far while implementing [Asteracea](https://github.com/Tamschi/Asteracea) and its related packages like the `lignin` group of crates. I'm making this post partially in response to [Raph Levien's Xilem: an architecture for UI in Rust](https://raphlinus.github.io/rust/gui/2022/05/07/ui-architecture.html), since I noticed we have largely similar approaches to app structure and lifecycle management (although we went for somewhat different solutions that are presented in superficially very different ways to the developer).

Funnily enough, our architectures are both named after plant biology. I [previously explained](https://knockout.chat/thread/33201) my choice as follows:

> **Why the name?**
>
> I'd started naming my projects after plants shortly before starting this one.
>
> [Asteraceae](https://en.wikipedia.org/wiki/Asteraceae) are often plain but wildly varied flowering plants.
My wish with this project is to create a "boring" system that is uninteresting by itself and highlights the user's individuality.
>
> The name also reflects that I'd like to support the creation of individual "web gardens" (small creative pages usually by individuals) as well as sustainable development of large enterprise apps (by encouraging maintainable code style through enterprise features like built-in dependency injection, as well as a green deployment due to (vastly) decreased runtime energy usage and hardware requirements).

(My system uses mutable but largely non-moving data structures, so its supporting crates like `lignin` or `rhizome` tend to be named after [structural](https://en.wikipedia.org/w/index.php?title=Lignin&oldid=1082275224) [components](https://en.wikipedia.org/wiki/Rhizome) rather than transport tissue, though.)

## A Word of Caution

First off, my professional background is largely web frontend development (about 1.5 years of specific experience?), and I don't exactly have a formal education in this space. Similarly, I picked up English largely while teaching myself how to program. There may be rough patches in terms of vocabulary ahead, in either regard.

I'll also have to rely on examples and comparisons a bit more, since I lack the theoretical knowledge to name the different existing UI framework API patterns.

As such, please take everything here with a grain of salt, and feel free to point out issues. I'm used to harsh criticism and don't mind as long as it attacks my ideas rather than something I have no control over.

## Motivation

I originally started work on Asteracea in late 2019, as part of a program I could host on my local network that would let me track itemised grocery bills and monitor individual product price changes. At the time, I also needed a break from JavaScript, but still decided to make it a website, so that I could use it easily on mobile without dealing with Android Studio.

Many of the choices I made and features I added are direct responses to frustrations I encountered while working as a consultant on web app projects, as well as as user of a fairly old computer, a phone with low system memory and frequently a slow internet connection.

I like websites that work also without JavaScript and don't start with a loading screen, won't unload other apps as soon as I browse to them, and don't hog the CPU. As a developer, I prefer to work with very strongly typed languages and to have documentation available directly in the IDE, to reduce the amount of time I spend on a feature and the amount of context switches I have to do.

Additionally, and this is purely personal preference, I love small indie projects and also like crafting my own web presence in detail. (I have *not* gotten around to doing the latter, for the most part.)  
As such, I didn't want to make a framework aimed *only* at larger scale deployments, but one that scales down nicely to even the smallest and simplest of pages and isn't prescriptive in terms of document structure.

## Goals

Asteracea is my attempt at making (web) frontend development both more convenient and more accessible, while raising the quality of the compiled applications.

The system is built from modular and often interchangeable parts, so while I'm working towards a turn-key bundle, you don't *have* to use my macro DSL to make your components compatible with mine. This is also to enable incremental upgrades of the platform without spilling all application code along with it. (Some glue may be required between distinct paradigms, where there could be a mismatch in the API shape exposed by individual components.)

Personally, both boilerplate and syntactic noise irk me though, so I created a relatively concise macro transform that translates symbols and keywords into structural aspects of the component, while identifiers are mostly used only for application-level constructs.

## Problems

The main issue with implementing a classic model-view-controller pattern in Rust is that lifecycle management of stateful hierarchical GUIs *is a huge chore*, largely due to callbacks that have to reach deep into encapsulated components (while mutability of inert data is much less of a problem).

Component-instantiating GUI frameworks like Angular or WinForms tend to be very boilerplate-heavy, buying a straightforward mental model with dense syntax and/or restated structure. (WinForms gets around this with a designer and generated code, but that's not a good option for web development, where a well-organised document structure often describes intent more than visual primitives.)  
Their strength is maintainable development at scale, as they hide transient local state very well and often allow for better code organisation than other paradigms.

Mainly reactive frameworks like eponymically React, which generate the GUI structure from only a render method, have greatly simplified syntax but often need workarounds for state management.
React's Hooks for example are very convenient, but they suffer from footguns related to control flow (that you can very reliably lint against, to be fair) and can't entirely remove initialisation from their hot update path without potentially changing behaviour. They also tend to scale less-than-ideally to more complex applications, mostly hurting code organisation and maintainability.

WPF is overall well-designed and its basic features are very accessible due to great first-party tooling, but full use of its advanced features is not all that well communicated (with a large gap between consuming and providing them) and the framework is non-portable, which is stifling broader adoption.  
However, many of its systems rely on externally-visible fairly direct mutability of components, which doesn't translate all that well into plain Rust.
(.NET as a whole is not great at tree-shaking unused code due to its runtime metaprogramming features, but that's not a problem with WPF in particular, just something that came up while I was thinking about how to make applications tiny enough for the clientside web.)

Immediate-mode GUIs like imgui or Unity's editor GUI system have the advantage of being able to reuse language constructs like loops directly to model aspects of a hierarchical GUI (and save many of the nested parentheses you see in the structurally similar reactive ones, so their syntax tends to be cleaner and more open-ended), but they mostly suffer from very inconvenient state management for child components.

## My Approach

I'm remixing existing ideas (including from all of the above).

If you look at the individual pieces that make up Asteracea, you'll likely notice that nearly all of them already exist in some shape or form elsewhere.

This framework aims to be "boring":

- The macro DSL is mostly contextless and generates unspectacular code you could easily hand-write (if you didn't mind *a lot* of verbosity and a bit of straightforward `unsafe` code for pin projections),
- the procedural macro lowers syntactic sugar in steps (both by transforming and reparsing in terms of its own syntax, and by delegating to existing general-purpose macros in its output),
- the generated HTML- and DOM-structure is no-frills as-if-handwritten, with no structural restrictions like mandatory custom elements and
- there are no surprises that would suddenly lower app performance because you weren't explicit enough.

The one original concept that I didn't see elsewhere before are **interlaced local scopes**, though I wouldn't be surprised if that has been done elsewhere, as it's a straightforward source code transformation.

[Reference-counting through direct payload borrows](https://blog.schichler.dev/posts/Intrusive-Smart-Pointers-+-Heap-Only-Types-=/) is something I came up with on a whim, but later learned already has [standard library support](https://en.cppreference.com/w/cpp/memory/enable_shared_from_this) in C++ (although in a slightly different way that doesn't mesh with strict provenance in Rust).

I'll annotate from where I lifted different concepts below each heading.

## My Solutions

Everything explained here is implemented and functional (on some branch in the repository, but mostly indeed *develop*), unless otherwise noted. You're invited to have a go at playing around with it, but keep in mind that there are some usability holes (and no standard library worth mentioning), and that some of the syntax is subject to change as I continue to simplify it.

There is a [Zulip Stream](https://iter-square.zulipchat.com/#narrow/stream/303796-project.2FAsteracea) for this project, in case you have questions or would like to give feedback on this post.

Apologies for the outdated versions on Crates.io; I started work on larger changes a while back and haven't finished polishing and documenting everything yet.

### Interlaced Local Scopes for Localised Semantics

The smallest, empty, component, which is a ZST, does not have inherent identity, does not incur allocations and does not generate output in either HTML or DOM, is roughly this:

```rust
asteracea::component! {
  Empty()()

  []
}
```

Which likely looks pretty odd. (Yes, that's two parameter lists.)

I went with a use-what-you-need approach to reduce the boilerplate required for simple components. **Stateful and pure reactive components are unified, with no baseline runtime overhead.** There *are* some trade-offs in updating the DOM, as the underlying `lignin` is a classic, so far double-buffered, diffed VDOM for easier modularity and platform-independence.

I'll explain the basic structure in terms of this counter component:

```rust
use asteracea::services::Invalidator;
use lignin::web::{Event, Materialize};
use std::sync::atomic::{AtomicUsize, Ordering};

asteracea::component! {
  /// A simple counter.
  pub(crate) Counter(
    priv dyn invalidator: dyn Invalidator,
    starting_count: usize,
  )(
    class?: &'bump str,
    button_text: &str = "Click me!",
  )

  <div
    .class?={class}

    let self.count = AtomicUsize::new(starting_count);
    !"This button was clicked {} times:"(self.count.load(Ordering::Relaxed))
    <button
      !(button_text)
      on bubble click = active Self::on_click
    >
  /div>
}

impl Counter {
  fn on_click(&self, event: Event) {
    // This needs work.
    let event: web_sys::Event = event.materialize();
    event.stop_propagation();

    self.count.fetch_add(1, Ordering::Relaxed);
    self.invalidator.invalidate_with_context(None);
  }
}
```

(Embedding the code here isn't ideal, since it loses the semantic highlights it normally has via rust-analyzer. [Screenshot](/assets/img/posts/2022-05-09-Asteracea/Counter-syntax-highlights.png))

Components are struct types with some associated functions, so they accept documentation and a visibility, and have a name that's an item identifier in their containing scope. (First two lines inside the macro.)

Next are the constructor parameters, in the first pair of parentheses:

- `dyn name: Type` uses the dependency injection mechanism (inspired by Angular) to retrieve a value and bind it to `name`. Meanwhile, `Type` acts as a token here and not only controls what is retrieved, but also how it is made available, and, if applicable, how it is lazily injected into the dependency tree. (The entry point here is the trait `rhizome::sync::Extract`, in my development version as of now.)

  A `dyn Trait` should usually extract itself as pinning sharing resource handle, which keeps the resource tree node its instance is stored in alive.

  The resource tree itself is sparse and can "skip" levels in the component hierarchy, so there is no overhead from components that don't interact with it.

- Prefixing a constructor parameter declaration with a visibility declares a field directly in the component and finally assigns the argument (whether extracted or plain) to it. (Lifted verbatim from Typescript.)

- `starting_count: usize,` declares a plain constructor parameter. All parameters are named, which is inspired by HTML attributes, and to a smaller extent by how properties can be assigned in Angular templates. The implementation is statically validated and should have next-to-no overhead thanks to the *typed-builder* crate, though there is some room for improvement in the implementation details (i.e. no easy repeatable parameters, and high complexity of optional arguments (which are distinct from optional parameters)).

Next is the render parameter list.

- This list is used for transient values that are provided each time the component is rendered, but may flow into the generated VDOM by reference if they are annotated with the special `'bump` lifetime.

- Placing a `?` after its name makes the parameter optional. The outwards-visible type is unchanged, but internally, it is wrapped in an `Option<_>`.

- An alternative to optional parameters are default arguments, written as `= expr` in their respective parameter definition. These are evaluated for each call where the argument wasn't specified and have access to preceding parameters. (Inspired by… Python I think? The semantics are different.)

A return type can be optionally specified after the render parameters, but generally this is automatic and a drop handle wrapping a VDOM node that can refer to other nodes in the bump allocator that was given to the render method by the app runtime.

-----

Next is the main original feature of Asteracea, a **mixed-style component body**. "Mixed-style" has a dual meaning here:

- The body is translated into both a constructor (`::new(…)`) and a VDOM-builder (`::render(self: Pin<&Self>, …)`).

  Each piece of plain Rust that appears in this body is quoted into either the one or the other, so distinct sets of local variables are present in each and `self` is only available in `.render`.

- The paradigm is mixed-declarative-imperative:

  - You get painless state management like in React, with **single statements that take care of both declaration and initialisation of local state**.
  - You can freely use (certain) flow control statements like `for`-loops without wrapping them in boilerplate.
    - Some differences apply: For example, loops expected to generate a value from each iteration, but this value can be the empty node `[]`. You can still use the normal versions inside a Rust-block-expression.
  - **This is a smooth mix**: Control flow (generally) translates into stored expression state management, so it's safe to declare more fields wherever, **right where you need them**. (There is no implicit cross-talk between loop iterations or branches.)

I'll continue line by line again:

- `<div` is an opening tag. These can either be standard HTML elements as identifier (which statically validates them to some extent and enables context help (See screenshot below.)), or

  ![A rust-analyzer popup with information on the &lt;div> element, with the start of a section on accessibility.](/assets/img/posts/2022-05-09-Asteracea/context-help.png)

  alternatively the element name can be written as strong literal (`"custom-element"`), which allows more flexibility at the expense of validation.

  To use an Asteracea-generated component as child, you would write `<*Child`, with an asterisk before the identifier. You can also write `<{expr}` to only render or transclude such a child component, without instantiating it.

- `.class?={class}`: This is an optional argument (in this case an optional attribute), only set if the value is `Some(…)` or `true` and fully absent if it is `None` or `false`. This also works on `*Child`ren, but only with `Option<_>`s.

  HTML attributes and render arguments are prefixed with a single `.` here. For HTML elements, the identifier can be replaced with a string literal like `"data-myData"` to skip validation.

  Child components may additionally accept constructor parameters prefixed with `*`. For example, the counter above could be placed inside a parent component as follows:

  ```rust
  <*Counter *starting_count={0}>
  ```

  Constructor argument expressions are placed in the surrounding constructor scope and in most cases run only once when the parent component is instantiated. However, any side-effects should ideally still be [idempotent](https://en.wikipedia.org/w/index.php?title=Idempotence&oldid=1077502153) regardless, to make debugging easier.

- ```rust
  let self.count = AtomicUsize::new(starting_count);
  ```

  This is React's `useState`, except that it can be placed anywhere. **The Rust expression on the right is constructor-scoped**, so it can see `starting_count` but not, for example, `button_text`.

  > The field is statically-typed. The above is actually a shorthand for:
  >
  > ```rust
  > let self.count: AtomicUsize = AtomicUsize::new(starting_count);
  > ```
  >
  > I used a bit of macro-magic to make that possible, as there is unfortunately no true field type inference.

  Fields declared this way can also be published (Their visibility follows `let` but is normally the implicit one.), though in this case that's not a good idea since setting it directly would not invalidate the rendered GUI state.

- The next line does string formatting: `!"format string"(args)` is the general pattern, though the implementation specifics are delegated to `bumpalo`.

  You can write `!(arg)` to imply the format string `"{}"`.

- `<button` - a nested HTML element, one of the recursion points of this grammar. You can also nest child components, and you can nest HTML elements and child components inside a container component to transclude them. (More on that later: Asteracea's transclusion is a bit fancier than what e.g. Angular or React can do, closer to WPF's in power.)

- The next line is just string formatting again, which brings us to:

  ```rust
  on bubble click = active Self::on_click
  ```

  Event handlers are currently the most shaky aspect of Asteracea and I'll likely have to rework some of their details a bit, so I'll be brief:

  Event bindings are on average allocation free (callback registry with drop notifications) and the use of modifiers (`bubble` vs. `capture` vs. nothing, and use of `active` after `=` to `event.prevent_default()`) is statically validated if the event is. (As usual, you can use a string literal for the event name to skip validation.)

  The handler can have a number of different signatures, and can also be written inline as currently `fn (self, event) { … }` (not a closure).

  Event bindings on child components are not yet supported, but will use uniform syntax with event subscriptions on HTML elements once available. Support for bubbling event bindings outside the HTML DOM is up in the air; personally I find good direct events to be cleaner, and for skipping layers there's the DI system already.

- `>` closes an HTML element or child component without restating its name.

- `/div>` closes that HTML element while restating its name. This is validated statically and the element's context help is available on this closing tag.

### Few, Composite Allocations

(inspired by Rust's async blocks)

Asteracea relies very heavily on data inlining to reduce memory use and improve cache behaviour.

Most Asteracea-components don't allocate directly, and their use elsewhere also does not automatically incur an allocation, as child components are (non-generically) inlined into their parents.

There are a few exceptions to this: `box` expressions explicitly heap-allocate the storage for their contents, and e.g. `for` loops are storage container expressions that manage storage instances on the heap. Conversely, simple branches like `match` (or `if`, which in Asteracea is direct syntactic sugar for the former) can use fully inlined storage either as `enum` or `struct`.

As components must be pinned to be rendered, the `asteracea::component!` macro safely implements pin projections for the fields storing child component instances.

(If you create branches with vastly different storage sizes, that does seem to get flagged by Clippy. You can then `box` one or more of the branches to dynamically use less memory.)

### Rich Tooling Compatibility

Asteracea preserves source code spans and assigns those of synthetic tokens based on fine-grained context. This means that most error messages and warnings are already very precise with just rust-analyzer.

Additionally, there are custom messages for domain-specific errors, like in the following case:

```rust
on bubble error = active fn (self, _) {}
   ~~~~~~         ~~~~~~
```

- evaluation of constant value failed  
  the evaluated program panicked at 'Keyword `bubble` is not valid for this event; the event does not bubble.'
- evaluation of constant value failed  
  the evaluated program panicked at 'Keyword `active` is not valid for this event; the event is not cancellable.'

(This isn't perfect: Rustc's spans are less accurate than rust-analyzer's (but still useful) and I'd love to get rid of the `evaluation of constant value failed`, `the evaluated program panicked at '`, `'` parts entirely. It's in my eyes at least close to a dedicated editor integration, though, and [Error Lens](https://marketplace.visualstudio.com/items?itemName=usernamehw.errorlens) is able to display the message inline with little clutter.)

Span preservation also gives you access to some rust-analyzer quick fixes inside the macro, though not all of them currently work correctly. I'm not sure how much I can improve them with the current proc macro API on stable, so for now I'm biding my time before attempting higher levels of polish in this regard.

Additionally, you can step-debug into components somewhat decently. (There is room for improvement here though, likely by adjusting the `Span`s for generated code some more.)

### Keyed Repetition

(inspired by loops in Angular templates)

It's very easy to construct dynamic list displays using loops in the component body:

```rust
asteracea::component! {
    ListVisual()(
        // Side-note: Supporting this kind of parameter type is pretty tricky.
        items: impl IntoIterator<Item = &'_ SomeItem>,
    )

    <ul
        for item in items {
            <li
                bind <*CaptureItem *item={item}>
            >
        }
    /ul>
}
```

This list is auto-keyed (which has a bit of overhead vs. specifying the key type manually (also possible), [until `type … = impl …;` becomes available](https://github.com/rust-lang/rust/issues/63063)), which means **the storage contexts for its body are automatically reused, reordered, and reinitialised only as needed**.

There is a bit of an oddity here: The constructor parameter `*item` on `*CaptureItem` receives data originally from the render parameter `items`. This is possible because `bind` moves the constructor of its argument into the render scope (as Rust closure), running it once when first rendered.

Stored loop body state is dropped when the loop runs again and that item is missing.

(Key repetitions are fine, but it's strictly the last ones for each key that are added or removed.)

### Un-keyed Repetition

You can loop in the constructor of a component instead by writing `*for`. This is evaluated only once when the surrounding expression (usually the component) is initialised, has exactly the same semantics as a plain Rust loop (aside from generating items), and generates the VDOM a bit more efficiently than the render-scoped loops above.

### Transclusion and Parent/Container Parameters

(inspired by transclusion in Angular and attached properties in WPF)

My code calls these "parent parameters", but I'm not sure which term is better in practice.

Take snippet example for instance:

```rust
<*Router
  // I'll redo how the paths are specified.
  ->path={"/div/*"} <div>
  ->path={"/span/*"} <span>
>
```

Here, two child expressions are handed to the `Router` instance during rendering. (They are constructed eagerly with the expression that contains this code, but you can easily `defer` that in most cases. Here I haven't done it because purely HTML expressions don't need storage or construction.)

This functions via closures, so while outer variables are visible, the `Router` can decide which branch to actually render here each GUI frame.

The `->path` argument is fully statically typed and validated against `Router`'s render method signature, and passed along by value with each child.

Transclusion slots can be named and distinct slots can accept different sets of arguments. The child parameter slot on `Router` in this case is repeatable and anonymous. I haven't yet implemented good syntactic sugar for declaring these, so that's currently a bit cumbersome.

A single non-repeating anonymous content parameter can currently be declared as `..`, and can also be pasted as `..` in the component body. This is a placeholder and likely to change.

### Coloured Async and Named Slots

There isn't really much to say about these features, as they follow directly from Rust's interpretation of coroutines and child transclusion via (named in general) render parameters.

Asteracea components may be asynchronous and `.await`ed in asynchronous expressions, which may be the body of an asynchronous component or created by the `async` keyword.

Slots can be named (I used lifetime labels here, since that results in nice syntax highlights.) and a slot can also be set up to accept an asynchronous expression.

```rust
async fn future_text() -> String {
    "Like a record!".to_string()
}

asteracea::component! {
    Spinner()()

    "Spinning right 'round…"
}

asteracea::component! {
    async Async()()

    let self.text: String = future_text().await;
    !"{}"(self.text)
}

asteracea::component! {
    Instant()()

    <*Suspense
        'spinner: <*Spinner>
        'ready: async <*Async.await>
    >
}
```

(That's essentially a clone of React's `Suspense`, just Rust-y.)

The storage for both the `Spinner` and `Async` is managed by (and inlined into) `Instant`, so `Suspense` can be fairly¹ non-generic, as transclusion is largely type-erased.

However, `Suspense` controls how the underlying `Future` is driven (holding onto a cancellation token and scheduling a small driver-`Future` using an injected `ContentRuntime` implementation) and takes care of invalidation (by cloning and passing along an optionally-injected `Invalidator` handle).

### Dependency Injection

(inspired by Angular, but strictly at runtime)

It's quite easy to declare resource tokens for injection, here for example the `ContentRuntime` declaration in its entirety:

```rust
// src/services/content_runtime.rs

use crate::include::async_::ContentFuture;
use rhizome::sync::derive_dependency;

/// A resource used by [`Suspense`](`crate::components::Suspense`) to schedule [`ContentFuture`]s.
pub trait ContentRuntime {
    fn start_content_future(&self, content_future: ContentFuture);
}
derive_dependency!(dyn ContentRuntime);

// Specific implementation:
impl<F: Fn(ContentFuture)> ContentRuntime for F {
    fn start_content_future(&self, content_future: ContentFuture) {
        self(content_future)
    }
}
```

(Injection of concrete data-holding types is set up a bit differently.)

As `ContentRuntime` in particular is blanket-implemented over certain closures, providing an implementation to your app is then as easy as writing:

```rust
// Given to the root component manually, but otherwise managed implicitly.
let root = Node::new(TypeId::of::<()>());

<dyn ContentRuntime>::inject(root.as_ref(), |content_future| {
    // `ContentFuture` is `'static + Unpin + Send + Future<Output = ()> + FusedFuture` and completely type-erased and semantically fire-and-forget,
    // and as such trivially compatible with practically every single Rust async runtime out there.
});
```

A container component's dependency injection node is parent to that of transcluded children. This allows `Invalidator`-interception for memoisation, for example.

As mentioned above, dependency injection into components is done by declaring a constructor parameters like

```rust
dyn runtime: dyn ContentRuntime,
```

but it's also possible to not strictly require the runtime by making the parameter optional:

```rust
dyn runtime?: dyn ContentRuntime,
```

### Memoisation

Between Invalidator injection, transclusion that flows the dependency context, and a drop-guarded VDOM, it's *relatively* straightforward to implement a memoisation component usable like this:

```rust
<*Memo
  // …further content…
>
```

And if you need to externally invalidate the `Memo`, you could name the field it is stored in to call methods on it:

```rust
<*Memo priv memo
  // …further content…
>

// …

self.memo.invalidate();
```

(My current memoisation component has a slightly different API, is on a feature branch, and is not in a clean shape. I'll likely optimise and clean it only after working on some other features first.)

### Sparse VDOM Drop Guards

The VDOM tree itself can be trivially dropped, so double-buffering it with a rotating pair of bump allocators is very efficient.

However, the memoisation component above must know when it's safe to drop a cached version of the VDOM, without direct knowledge of the main allocators' `unsafe` rotation at the app root.

Relying on a safety contract that prescribes an app lifecycle with repeating elements seemed error-prone, so instead Asteracea uses sparsely aggregated drop guard trees stored in the same bump allocators as the VDOM nodes.

These *may* contain a type-erased drop notification (as well as the VDOM node they guard), but most importantly can be `unsafe`ly split into the notification and VDOM node.

The component macro aggregates the former from child components, only pushing a pair into the allocator where collisions happen, and then composes them with the VDOM node it created to create a safe return value.

If an error or unwind happens while these parts are split, the drop notification is sent and the macro guarantees that the formerly-guarded VDOM nodes are never accessed.

### Server-side Rendering and Hydration

As Asteracea is fundamentally platform-agnostic, it's possible to run applications natively on a server without changes to the application code. (If you need different output, you can reconfigure aspects of an app through dependency injection, e.g. by not injecting a user credentials service or by injecting dummy async runtimes that never poll the `Future`'s.)

`lignin-html` can render `lignin` VDOMs into HTML documents, and `lignin-dom` can read the DOM tree into a VDOM tree, effectively hydrating it in place on first diff.

### Element Bindings

Element bindings function similarly to event subscriptions and give a component running client-side access to the DOM element instance, by notifying it of changes and asking it to clean up when removed from the rendered view.

I haven't really given this feature much thought yet, but it's there and should be enough to host JavaScript components.

### Room for Modifications

The lignin DOM update specification carves out some niches for uncontrolled modifications of the page structure, to make it easier for users to adjust the appearance of pages or add functionality using e.g. web extensions.

With at least my differ, apps won't interfere with extra child nodes in an element as long as they follow the app-managed ones, or extra attributes or extra event bindings. (There is no external notification in cases where a DOM element instance happens to be repurposed, though, so extensions must subscribe to DOM changes to stay in sync.)

Additionally, the differ is at the same time resilient enough to detect inconsistencies with the tolerated DOM state and recreate parts of it more aggressively where needed.

### A Declarative Compile-Time Schema Library

Asteracea's knowledge of HTML is provided by the `lignin-schema` crate, the source code of which you can find here: [lignin-schema/src/lib.rs](https://github.com/Tamschi/lignin-schema/blob/develop/src/lib.rs)

The macros encode information about elements, attributes and events into the Rust type system and attach meta data (documentation and deprecations) as attributes, while the `asteracea::component!` macro does not have this information and instead just emits validating const expressions and constructs the relevant type paths.

The actual schema validation is then done only by the Rust compiler, which also makes it possible to have automatic in-editor completions for element names and for rust-analyzer to provide documentation on hover. (The macro could be more lenient to allow completions to work in more cases.)

> You may notice that one of the macro [upper-cases all element names](https://github.com/Tamschi/lignin-schema/blob/a60d7ac84ded70858cfa82cc41826585697d9085/src/lib.rs#L84). I somewhat boldly assumed a differ might want to use `Element.tagName` inside an HTML document without doing a case-sensitive comparison here, but maybe lower-casing everything would be better in light of Brotli compression.
>
> I don't think it really matters all that much when using a double-buffered VDOM, at least, since the renderer would only have to adjust casings once during hydration.

### Plain Extra Impls

As the entirety of component's state is stored in "just fields", it's easy to extend a component's API.

For example, the following could be added to the counter component above's module to give its parent access to the counter state:

```rust
impl Counter {
  pub fn count(&self) -> usize {
    self.count.load(Ordering::Relaxed)
  }

  pub fn increment(&self) {
      self.count.fetch_add(1, Ordering::Relaxed);
  }
}
```

As long as the parent binds the instance to a name, like here…

```rust
asteracea::component! {
  Parent()()

  <*Counter priv counter
    *starting_count={0}
  >
}
```

It can then call these as e.g. `self.counter.count()`.

Some methods may require a `Pin<&Self>`. For fields that require pinning, like child components, a matching pin projection method is also available. In this case, `self.counter_pinned().count()` would also work that way as long as `self` is at least a `Pin<&Parent>`.

### No-Effort Instrumentation

You only have to enable Asteracea's `"tracing"` feature to automatically instrument all constructors and render methods with tracing spans and log all their arguments. (This uses [auto-deref-specialisation](https://lukaskalbertodt.github.io/2019/12/05/generalized-autoref-based-specialization.html) internally, so you get meaningful argument logs depending on which traits are available on them, without having to worry about incompatibilities.)

> Please wrap any sensitive information you pass around in your program in a debug-opaque newtype to avoid accidental logging. The `lignin-…` crates, once published to Crates.io in their instrumented version, similarly should provide only redacted logs by default, unless content logging is explicitly enabled via a feature.)

You also get nice performance traces in the browser if you use [tracing-wasm](https://lib.rs/crates/tracing-wasm). I'd like to eventually write a proper debug interface and browser extension to inspect the app state, but for now that's quite far off.

One caveat here is that `async` constructors aren't quite properly instrumented due to [some difficulties](https://github.com/tokio-rs/tracing/pull/1819) with the `tracing::instrument` attribute macro. It seems my PR in this regard might land soon though, at which point adjusting Asteracea to use that macro again should be quick and easy.

There is also [a potential parameter name collision](https://github.com/Tamschi/Asteracea/issues/86) with this feature that still needs to be solved, though ideally upstream.

## Odd Features

I'll probably scrap or evolve these from their current form, since they have usability drawbacks.

### Thread Safety Inference

Asteracea components (by default only in the same crate) can transitively infer the thread-safety tag of their resulting VDOM, entirely at compile time.

At least in theory that, since there seem to be frequent edge cases where this trips up type inference somewhat. (The core hack is deanonymization of opaque (`impl …`) return types through the auto trait side channel. You can find more information on that in the [`lignin::auto_safety`](https://docs.rs/lignin/0.1.0/lignin/auto_safety/index.html) docs.)

I'm considering letting all component-generated VDOM be only `!Sync` by default, while keeping the option to safely state otherwise. This would remove those edge cases (mostly dependency loops) where inference suddenly fails, and would *probably* improve build times a little.

### Native GUI Targets

There's nothing really stopping you from rendering a `lignin` VDOM in terms of a native GUI framework, however this currently maybe isn't the best fit depending on the framework in question.

As Asteracea doesn't really take care of event bubbling and assumes all standard elements are present, a fairly thick glue layer may be required to make this work nicely.

I made a quick proof of concept in this space, and it works well with low requirements, but this is not something I plan to pursue immediately.

## Future Work

There are a few open points that I still haven't figured out:

### More syntax/syntax revisions

  I'd like to add plain `let` (and `*let`) bindings directly to the body grammar, and in exchange remove the `with {}` blocks that paste Rust code into the constructor or render function.

  Flow control expressions should consistently use `{}` around their branches, while embedded Rust expressions should be more explicit than that.

  There are also some flow control expressions or expression variants that aren't implemented yet.

  Attribute/argument syntax is a bit too verbose. I should be able to make the `{}` optional (though expressions with `.` will have to be parenthesised, still).

### An efficient render-context

This would make it easier to propagate transient state along the component tree, with the option to later remove contents from it without re-creating the affected components.

*rhizome* is not suitable for this, as it unconditionally allocates at least twice for each new populated resource scope and is inflexible regarding removals.

### A mockable asynchronous HTTP client

This should be a trait in Asteracea's standard library, to be used as injected dependency.

(I'll likely clone `hyper`'s API for this on some level, but I haven't really looked into this.)

### Optimisation

Asteracea feels fast as-is, but there's likely a bunch of potential in giving the crates I proof-of-concept'd as dependencies any optimisation pass at all.

(I've constructed the public crate APIs with efficiency in mind already, but I took some shortcuts here and there as far as the internals go. This is my unpaid hobbyist project, after all, so I have to cut corners *somewhere* ;-) )

### A `Remnant` API and implementation

There's currently only a placeholder VDOM node variant.

"Remnants" (as I call them) are (to be) lingering pieces of the DOM that are preserved for a while even after they are removed from the VDOM, existing outside the usual app update flow. This makes them useful for animating-out nodes.

### Raw HTML Pasting

I haven't added this to the VDOM since I personally don't need it, but someone is going to want that feature before long.

### Data Binding

(This is a wishlist feature that I haven't gotten around to seriously working on yet. I only have vague ideas how to implement this.)

Declaring `Cell`s and other interior-mutable fields seems okay when using the shorthand syntax, but I'd like to simplify how they are updated in high-level components. Take the following **currently not functional syntax sketch** for example (inspired by Angular):

```rust
asteracea::component! {
  DataBinding()()

  let self.data = RefCell::new("".to_string());

  <*TextField .(value)={&self.data}><br>
  "The text is currently: " !(self.data.borrow())
}
```

The details of the binding implementation can be provided by a trait, similarly to how optional arguments work already. This way, you could use a plain `Cell` for types that are `Copy`.

It *should* be possible to reuse the callback registry mechanism that DOM event subscriptions use here, with the control component (`TextField`) storing a `CallbackReference` it receives as render parameter. `lignin`'s [`CallbackRef`](https://docs.rs/lignin/0.1.0/lignin/callback_registry/struct.CallbackRef.html)s are opaque weak handles (meaning they contain only a number and are `Copy`), so there's little overhead to just replacing them on render.

Such data bindings should also automatically invalidate the current component using an implied `priv dyn __Asteracea__invalidator? = dyn ::asteracea::services::Invalidator` added to the constructor parameter list.

## Planned Features

The following are *in theory* solved problems, but implementing each solution would either be a fairly large amount of work for me right now or is lower-priority for other reasons.

### A component trait

Components are currently duck-typed, with a mix of attached methods and type inference hacks to instantiate the appropriate arguments builders.

It should be possible to at least partially implement a trait for the interface instead, which would make component implementations *not* using the `component!` macro a bit easier.

### Repeat parameters

Similarly to optional parameters with `?`, the following declarations should also be valid in the parameter lists:

```rust
zero_or_more*: Type, // Vec<_>?
one_or_more+: Type, // `Vec1<_>` or similar
optionally_one_or_more+?: Type, // `Option<Vec1<_>>`
optionally_zero_or_more*?: Type, // largely just for completeness, `Option<Vec<_>>`
```

Then, on the caller side, it should be possible to repeatedly add arguments for these parameters (or transcluded children to the same variadic slot!) and/or to spread an `IntoIter<Item = Type>` into them.

I started work on the necessary infrastructure [quite a while ago](https://github.com/idanarye/rust-typed-builder/pull/46), but so far haven't found the time and peace of mind to complete this pull request.

### Better missing argument errors on child components

Now that const expression panics are available and appear as compile-time errors, it should be fairly straightforward to validate argument presence that way (using the same kind of method chaining as the actual builder, but without argument values). The raised panic would then appear as error on the child component's identifier or reference-expression, and could clearly list which fields are still missing.

(Ideally this would replace the deprecation message and errors from *typed-builder*, but I'm not entirely certain how feasible that is. I *think* it will be possible once [inline `const { … }` blocks](https://github.com/rust-lang/rust/issues/76001) are available, as then this block could provide the initial builder and, on error, result in a somewhat more lenient vacant dummy type instead.)

## Other Issues

For various additional rough edges, please see [Asteracea's issues](https://github.com/Tamschi/Asteracea/issues) on GitHub.

## How to support this project or me personally

There are two good ways for individuals to contribute to Asteracea's development right now:

- You can send me feedback or questions

  If a feature turns out to be unclear, that means I either have to add better documentation for it or revise the feature itself.

  (I'm writing a guide book in parallel to development, [deployed automatically](https://schichler.dev/Asteracea/) from and tested against *develop*. The "Introduction" page is a bit outdated; I'll get around to updating it eventually.)

- You can contribute code to related repositories

  The main Asteracea repository is too in flux right now to efficiently take contributions, but there are a number of dependencies that have a stable API but are internally not optimised well or incomplete.

  These crates, for example *tiptoe*, also mostly have a generic API rather than one designed only for Asteracea, so they may be worth a look for your own projects too.

I'm not currently in a position where I could invest small monetary contributions efficiently to further Asteracea's development. (The most direct effect would be letting me eat better and showing me that there's tangible interest in this side project of mine, which **may** lead to me spending more time on it and coding a bit faster.)

If you'd like to tip me regardless, for example for this blog post here, I now have [Ko-fi](https://ko-fi.com/tamme) and [GitHub Sponsors](https://github.com/sponsors/Tamschi) profiles. If you happen to use RPG Maker MV, you can also have a look at [my Itch.io page](https://tamschi.itch.io/) where I published some tools and plugins.

For anything else, you can reach me at the email address available from the sidebar.

## Project repositories

<!-- markdownlint-disable no-inline-html -->

|||
|---|---|
|[Asteracea](https://github.com/Tamschi/Asteracea)|Component macro DSL and beginnings of a standard library.|
|[lignin](https://github.com/Tamschi/lignin)|VDOM and callbacks.|
|[lignin-schema](https://github.com/Tamschi/lignin-schema)|Declarative (superficial) HTML, SVG and MathML schema, encoded in Rust's type system.<br>The name is something of a hold-over; there is no dependency relationship with `lignin` anymore.|
|[lignin-html](https://github.com/Tamschi/lignin-html)|(Partially-validating) VDOM-to-HTML renderer.|
|[lignin-dom](https://github.com/Tamschi/lignin-dom)|DOM hydration and diffing.|
|[rhizome](https://github.com/Tamschi/rhizome)|A lightweight runtime dependency injection container/reference-counted context tree.
|[fruit-salad](https://github.com/Tamschi/fruit-salad)|Trait object downcasts, among other features. Used by rhizome.|
|[pinus](https://github.com/Tamschi/pinus)|Value-pinning B-tree maps that can be added to through shared references. Used by rhizome.|
|[tiptoe](https://github.com/Tamschi/tiptoe)|[Intrusively reference-counting smart pointers.](https://blog.schichler.dev/posts/Intrusive-Smart-Pointers-+-Heap-Only-Types-=/) Used by rhizome.|

## Additional repositories

|||
|---|---|
|[lignin-azul](https://github.com/Tamschi/lignin-azul),<br> and [asteracea-native-windows-gui](https://github.com/Tamschi/asteracea-native-windows-gui) and<br> [lignin-native-windows-gui](https://github.com/Tamschi/lignin-native-windows-gui)|Sketches/proofs of concept for using Asteracea to implement native GUIs.<br> In practice, it might be a good idea to make `lignin`'s VDOM nodes generic<br> over the element type type, to allow switching the `&str`s for an `enum`.
|[an-asteracea-app](https://github.com/Tamschi/an-asteracea-app)|WIP single page application demo project. Very rough, somewhat outdated,<br> but [shows the rotating VDOM buffers](https://github.com/Tamschi/an-asteracea-app/blob/0b00d0613aa9ad594cf4454cc090cd67e9273aa0/src/lib.rs#L69-L90).

<!-- markdownlint-enable no-inline-html -->

## Footnotes

### ¹ Suspense

This is the source code for the suspense component in its entirety:

```rust
use crate::{
  include::{
    async_::{AsyncContent, ContentSubscription, Synchronized},
    render_callback::RenderOnce,
  },
  services::{ContentRuntime, Invalidator},
  __::Built,
};
use lignin::{Guard, ThreadSafety};
use std::cell::UnsafeCell;
use typed_builder::TypedBuilder;

#[derive(TypedBuilder)]
pub struct NoParentParameters {}
impl Built for NoParentParameters {
  type Builder = NoParentParametersBuilder<()>;

  fn builder() -> Self::Builder {
    Self::builder()
  }
}

asteracea::component! {
  /// Renders `'spinner` unless `'ready` has finished construction.
  ///
  /// `'ready`'s construction is scheduled automatically.
  pub Suspense(
    priv dyn runtime: dyn ContentRuntime,
    priv dyn invalidator?: dyn Invalidator,
  )<S: 'bump + ThreadSafety>(
    // Clearly missing syntactic sugar for these transclusion slots:
    spinner: (NoParentParameters, Box<RenderOnce<'_, 'bump, S>>),
    mut ready: (NoParentParameters, AsyncContent<'_, RenderOnce<'_, 'bump, S>>),
  ) -> Guard::<'bump, S>

  // Cancels on drop via strong/weak `Arc` reference counting.
  let self.subscription = UnsafeCell::<Option<ContentSubscription>>::new(None);

  {
    match ready.1.synchronize(unsafe{&mut *self.subscription.get()}) {
      Synchronized::Unchanged => (),
      Synchronized::Reset(future) => self.runtime.start_content_future(future, self.invalidator.clone()),
    }

    ready.1.render(bump).unwrap_or_else(|| (spinner.1)(bump))?
  }
}
```

As you can see, it's quite concise already, and only generic over the thread-safety of the resulting VDOM.

The part of the body wrapped in `{}` is plain Rust, as there is not much state management to be done here and the transcluded content already generates the finished drop-guarded VDOM handles. I plan to make the syntax for Rust blocks more explicit as I continue to move to brace-bodied flow control expressions.
