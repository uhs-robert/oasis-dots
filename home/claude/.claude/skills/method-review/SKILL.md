---
name: method-review
description: Review code for method-level clarity by applying reuse, decomposition, conditional structure, boolean simplification, and unnecessary-machinery principles. Use when the user asks to simplify or clean up code or a diff, clean up conditionals, flatten logic, reduce complexity, or improve how individual functions are expressed. For whether the overall design fits the problem, use structural-review.
---

# Method Review

Review whether each method is expressed as clearly as it could be. "Method"
means any unit of behavior: a function, method, closure, signal handler or
shell function. The examples are Ruby, but every principle applies in any
language. Walk changed or flagged methods and apply the principles below as lenses — not as a
checklist to run exhaustively, but as tools to reach for when something reads
harder than it should.

## Process

1. Identify new or modified methods in scope. With no target named, use the
   methods the current diff adds or changes.
2. For each method, check whether any of the principles below apply.
3. For each finding: state what's hard to read, which principle it violates, and
   a concrete suggestion.
4. Report the findings without editing, then offer to apply them.

## Principles

### Reuse

**Search before you write.** Before accepting new helper code, search the
codebase for an existing function, module or utility that already does the
job, and for near-duplicates of the new code elsewhere. A finding here names
the existing code to call instead, by path.

### Decomposition

**Single level of abstraction.** A method should read at one level. When it
mixes high-level intent with low-level mechanics, extract the low-level pieces
into private methods so the public method reads as *what* happens and the
private methods handle *how*.

```ruby
# before
def process_order(order)
  total = order.items.sum { |i| i.price * i.quantity }
  total *= 0.9 if order.coupon_applied?
  charge_card(order.card_token, total)
  OrderMailer.confirmation(order).deliver_later
end

# after
def process_order(order)
  total = calculate_total(order)
  charge_card(order.card_token, total)
  send_confirmation(order)
end
```

**Separate branching from doing.** Code that branches should only call out to
other methods — it doesn't get to contain implementation details. This makes
each branch's behavior independently readable, testable, and reusable.

```ruby
# before
def save(for_real:)
  if for_real
    File.open("#{@title}.txt", "w") { |f| f.puts @title; f.puts @body }
  else
    $stdout.puts "PREVIEW"
    $stdout.puts @title
  end
end

# after
def save(for_real:)
  if for_real
    save_to_file
  else
    output_preview
  end
end
```

**Separate caching from calculation.** When a method memoizes, split the
caching concern (Ruby's `||=`, a lazy-init check, a cache table lookup) from
the work it caches. This keeps each piece readable
and makes it easy to bypass the cache when needed.

### Conditional structure

**Push conditionals up the decision tree.** When independent conditions are
scattered throughout a method, they create a combinatorial explosion of paths.
Instead, branch early on the real decision and be honest about the fact that
there are multiple distinct paths. Flat conditionals at the top of a method
are easier to read, reason about, and debug than deeply nested ones.

```ruby
# Processing all steps of a multi-step form on one endpoint: independent
# conditionals on parameters vs step-based branching
#
# before: 16 possible paths, most "should never happen"
def process(params)
  fetch_alma_mater if params[:school].present?
  confirm_email if params[:email].present?
  verify_number if params[:phone].present? && @user.active?
  reset_timer if params[:school].present? || params[:email].present?
end

# after: 3 explicit paths
case step
when :bio     then process_bio
when :address then process_address
when :socials then process_socials
end
```

### Boolean simplification

Conditionals that return booleans are often reimplementing basic operators.
When you spot an `if`/`else` that returns `true`/`false`, check whether it's
just identity, negation, `&&`, or `||` in disguise.

```ruby
# before: reimplements negation
def reader?
  if admin?
    false
  else
    true
  end
end

# after
def reader?
  !admin?
end
```

For complex boolean methods with multiple variables, a truth table can help
reveal which operator the early-return chain is reimplementing.

### Unnecessary machinery

**Don't build collections iteratively.** When code initializes an empty
collection and appends to it in a loop, it's usually reimplementing the
language's map, filter, flat-map or reduce (in shell, often a pipeline).

```ruby
# before
def signer_key_ids
  result = []
  signers.each { |s| result << s.key_id }
  result
end

# after
def signer_key_ids
  signers.map(&:key_id)
end
```

**Push block logic to the objects being iterated.** When a loop body, callback
or closure reaches into an object's internals, that logic usually belongs on
the object (or its module) as a method. This fixes feature envy and builds
richer domain objects.

**Avoid special cases through better abstractions.** Every conditional is a
special case readers must parse. Sometimes a better abstraction eliminates it
entirely — null objects instead of nil checks, empty collections instead of
presence guards, polymorphism instead of type branching.

## Scope

- Takes the overall approach as settled. Does not question the decomposition
  into classes/services or the choice of data structures — those are
  macro-structural concerns.
- Suggests restructurings (extract methods, flatten conditionals) but gives
  extracted methods working names rather than polished ones — naming is a
  separate concern.
- Focuses on judgment calls about code structure. Mechanical language idioms
  and formatting belong to the linter. Framework-level judgment is a separate
  concern.

## Further reading

If the user asks "why" about a recommendation, check
[references.md](references.md) for related blog posts to point them toward.
