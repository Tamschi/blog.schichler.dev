---
title: Some thoughts on Bubble
date: 2021-07-19 19:51:00 +0200
categories: [Web Development]
tags: [tooling, evaluation, critique, PaaS]
preview: Examination of a "No Code" web development system.
redirects:
  - /some-thoughts-on-bubble
  - /some-thoughts-on-bubble-ckraxckvl0tlcz6s1d72ahse6
image:
  src: /assets/img/posts/2021-07-19-Some thoughts on Bubble/6nn2cNiE2.jpg
  width: 1600
  height: 840
  alt: |-
    A website in the DOM inspector. There is a large amount of nested `<div>`s, each with one or two classes and then a long `style=` attribute positioning it (often absolutely) on the page, culminating in a `<font>` element in the last row at the lowest level of nesting.
---

I tend to be a bit doubtful if there's a new technological trend that I know has in reality been tried (to mediocre success) for upwards of twenty years, to varying levels of fanfare. This also applies to "without coding" or "No Code" software or service creation.

I shared some general scepticism in this regard when I came across it on Twitter, and got a reply pointing out a specific implementation:

<https://twitter.com/nocodechris/status/1417035866011275266>

Technology changes, so it would be unfair to immediately dismiss this.

I spent about an hour evaluating Bubble, by watching a video tutorial, going through the onboarding process, playing around a bit with the editor, looking through the template selection and examining a few sites built with it. That's not enough for a thorough review, as the tool is complex enough to be the subject of multiple tutorial series, but it was enough to run into some rough edges, which I'll go over below.

- - -

Quick Navigation:

- [Poor output quality](#poor-output-quality)
- [Accessibility issues](#accessibility-issues)
- [Not no code](#not-no-code)
- [Cost](#cost)
- [Lock-in](#lock-in)
- [Conclusion](#conclusion)

- - -

## Poor output quality

This is the elephant in the room, so I'll go over it first.

Before continuing, I encourage you to visit [Bubble's showcase page](https://bubble.io/showcase). Play around with a few sites, resize the window, hover over parts of the page, inspect the document model.

Here's what I noticed while doing so:

- Pages are unexpectedly slow

  I believe this is due to a mixed over-reliance on both JavaScript and inline styling.

  No static version of the site is served (for which there is no technical reason; Especially with a WYSIWYG editor, it should be feasible to render at least an initial version of a page on the server). Instead, the page comes up completely blank with disabled scripts, and with enabled scripts takes about 1.5 seconds to show any content at all for a simple static page:

  ![Sprrk.ly and Network dev tools](/assets/img/posts/2021-07-19-Some thoughts on Bubble/zJuiu05zB.png)  
  (*The Sprrk.ly main page, which does not contain much or dynamic content, takes 1.5 seconds to show and over three seconds to stabilise.*)

  This isn't great in terms of end user experience, but it's not necessarily a complete deal breaker. However, it does mean that your site may perform considerably worse in places with poor connectivity, like in Germany for example. (I'm using a fast connection though, fortunately.)

  Something else you may have noticed is that many of the page's resources start loading very late. This could be improved considerably by adding them as `<link rel=reload as="…" href="…">` elements to the page's static HTML header.

- Lag

  There is a noticeable delay between resizing the browser window and the page reacting with a layout update, or there can even be a series of staggered layout updates.

  This occurs because Bubble seems to rely on JavaScript and absolute positioning to lay out elements on the page:

  ![Style attributes flashing in the DOM over about a second after the web page is resized.](/assets/img/posts/2021-07-19-Some thoughts on Bubble/KJfaRL0Af.gif) (*[goodgigs.app](https://goodgigs.app/)'s landing page takes quite a while to stabilise after a resize.*)

  The fix here would be to use a robust slot-based layout system with static CSS styles, but this would likely be incompatible with all existing Bubble apps.

  JavaScript-based layout like the above tends to drain device batteries quickly, turning away mobile users and users of low-power or currently energy-saving devices, where the performance impact is more noticeable.

- Wrong mouse cursors/inconsistently clickable elements

  It's a minor issue, but some of the pages I saw didn't use the correct mouse cursor appearance for clickable elements or had nested elements that made regions of their parent unexpectedly not clickable. I didn't see a way to adjust this in the editor, but it's likely fixable by writing some CSS.

## Accessibility issues

Bubble's editor has **zero** support for accessibility features. Seemingly not even image alt texts.  
Combined with a lack of support for semantic HTML, this makes sites built with it hard or in some cases impossible to use for many disabled Internet users.

(If you are unfamiliar with concept of web accessibility, here is a list of resources by the relevant standards body: [W3C WAI - Accessibility Fundamentals Overview](https://www.w3.org/WAI/fundamentals/))

Something I noticed that stood out to me negatively is that a (third-party) tutorial recommended using an "icon" element as custom-styled check-box. Bubble's plugin search dialog appears to use similar replacement elements, likely manually coded but still inaccessible.

While this is common for professional web developers to do in HTML too, we have to take care to add back the right semantics (like being able to use the tab key to navigate, [the right ARIA role](https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Roles/checkbox_role), or read-aloud checked-state information) to make the element usable not only visually and not only via mouse!

You can get a rough estimate of a page's accessibility using the Lighthouse tab in Chomium browsers' developer tools:

![Lighthouse summary for https://bubble.io/academy. Points are out of 100.
Performance: 32
Accessibility: 38
Best Practices: 80
SEO: 82
Progressive Web App: -
0-49: red/bad
50-89: orange
90-100: green/good](/assets/img/posts/2021-07-19-Some thoughts on Bubble/rjbH0fSfB.png) (*The Bubble website itself appears to be built using their tool, so it too fares badly.  
The rating varies by page, but the Academy one seemed like a typical content mix.*)

## Not no code

This is probably a matter of perspective, but Bubble sites appear to still require a lot of coding if you are looking to create a cohesive user experience. Take for example [this "Select All" button tutorial](https://www.nucode.co/lesson/how-to-create-a-select-all-feature-for-repeating-groups-in-your-bubble-app-1570154728531x958607275937235000):

<https://www.youtube.com/watch?v=ImJausGZLs4&t=170s>  
(*The video should start at 2:50, as the workflow is set up.*)

This looks a lot like coding to me. It's in English, but the complexity is about the same as if I'd write this in TypeScript or JavaScript. It's a little bit more cumbersome if you use the mouse like this, though.

What Bubble succeeds at is removing the barrier of entry for basic dynamic website creation, but you'll still have to either hire or become a coder to make something a bit more complex or convenient.  
The available options are metaphorically at your fingertips through popup lists, but I think it's still likely you'll have to look up tutorials to use them correctly, as there are not always [documentation](https://manual.bubble.io/) links.

In fairness: It's most likely possible to wrap this functionality into a plugin. However, this was not available when I looked for it in July 2021. If your specific feature hasn't been made available yet, you'll either have to click or write some code or pay someone for it.

## Cost

Not writing code costs a lot (relatively speaking).

As of writing this, the lowest-cost useful plan (that is: one that can actually deploy a live version) costs $25 monthly if paid annually, $29 on a true monthly basis.  
This comes with one editor (user) and 10GB storage, though seemingly no limit regarding the number of apps that can be deployed.

If you're an agency and would like to provide ongoing support using this platform, you will have to pay at least $71/month/person.

For comparison, generic dynamic hosting with similar specification seems to start around 2€ monthly, including top level domain registration. If you can code traditionally and want to support your product into a polished state, that's likely more economical, as Bubble's editor won't help much with those last 20% where you get rid of styling edge cases and general jank.  
(As Lighthouse mentions, optimizing site performance can also give you a major conversion rate boost. I'm not sure doing that is even possible on Bubble.)

If you're looking to host a static personal page, you can do that for free using GitHub Pages, or if you would like to avoid writing code, then Carrd lets you make basic SPAs for $9/year for three of those. (I'm paying a little more - $19/year with a limit of 10 - since I'm spicing mine up with a bit of JavaScript.)

## Lock-in

This might be a serious issue. I don't see any way a Bubble app could be portable between services, so if Bubble disappears, so will the apps built with it.

That said, since all useful plans are paid and have a significant margin, it's unlikely that the service will close down outright while there are still people relying on it, at least in terms of financial reasons. With a launch date in 2012 it's also *relatively* long-running, though I would have expected a much higher-quality user- and technical experience by now. The app feels more like a startup that launched its product between two and three years ago's.

## Conclusion

I still think that no-code or reduced-code service development is an interesting area, but it's *not quite there yet, still*, in my eyes.

As of right now, it still (in this case) appears to be a niche tool for a very specific group that's neither too wealthy nor too poor, not too skilled at web development but somewhat familiar with data processing, for applications that are not simple enough to work with static or purpose-bound hosting but also not complex enough to benefit from the scaling effects of frequent code reuse and a solid layout system.

It's rather ironic that [Bubble has a tutorial series on cloning famous services](https://bubble.io/how-to-build):  
While Bubble apps are potentially viable while small, Bubble's performance and accessibility issues make them a prime target for hostile clones.  
This means that, should an app built with Bubble be innovative enough to start blowing up, it's likely for an investor or programmer/designer team to come along, commission or create a performant clone of the same business model, and then eat away the original's market share through lower margins and better user experience.

Personally, I won't add Bubble to my toolset. For professional projects, it's easier and faster for me to write a website directly in Angular or React (or even in plain HTML, if it's simple enough), and to manage the database semi-manually.

For personal projects, I'm already stringing together specialised hosted solutions that are all-together easier to use and less expensive than what I could achieve through Bubble's interface as a single developer. (This is largely a result of tooling network effects. A more incremental, more compatible and more open no-code tool would likely work much better for me, but this couldn't exist as [#SaaS](https://hashnode.com/n/saas) or [#PaaS](https://hashnode.com/n/paas).)

<!-- markdownlint-disable no-empty-links -->

[↑](#) <!--(comments below)-->
