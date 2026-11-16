# Zone

An interactive fiction inspired by Tarkovsky's *Stalker* and the Strugatskys' *Roadside Picnic*. Unlike most IFs, you write (some) Ruby code to interact with the world.

You don't need to know Ruby to play... and if you do, be careful... things aren't always what they seem in the Zone.

## Requirements

- Ruby 4.0.1 (via rvm; see `.ruby-version`)
- Bundler

## Content

We can use fmt to word-aware wrap to 72 cols to help with formatting:

```bash
fmt -w 72 content/prologue/office.md
```

## Setup

```bash
cd ~/Code/zone
bundle install
```

## To Play

...wip...

## Tests

```bash
bundle exec rake test
```
