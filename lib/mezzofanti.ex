defmodule Mezzofanti do
  @moduledoc """
  The `Mezzofanti` module provides a way of localizing your application
  based on the [ICU message format](https://unicode-org.github.io/icu/).

  ## Differences and similarities to Gettext

  The API is similar to [Gettext](https://hexdocs.pm/gettext/Gettext.html),
  but with a number of important differences.
  The main difference (aside from the message format) is the following:

  In Gettext, you define a backend.
  The backend defines a number of macros.
  You use those macros to "mark" strings for translation
  so that Gettext can gather all translatable strings and persist them
  in `.po` and `.pot` files, which your translators can translate.

  In Mezzofanti, to mark strings for translation you *don't* need
  to define a backend.
  You just `use Mezzofanti` and then mark the strings for translation
  with the `Mezzofanti.translate/2` macro.
  Then, to *display* the translated strings, you do define a Mezzofanti backend.
  That backend will be able to extract translatable strings from your
  application and all your dependencies, so that you can translate
  everything in a centralized place.
  With Gettext, there it's nor possible to translate messages in dependencies,
  unless somehow the dependency provides you with an already created `.pot`
  file that you add to your application's, `.pot` files
  If you are translating user-visible strings
  *in a library meant to be imported by other projects*, you shouldn't
  define a Mezzofanti backend at all.
  The user's Mezzofanti backend will be able to extract the strings from your library.

  Unlike Gettext, where it might make sense to have more than one backend active
  at the same time, it never makes sense to have more than one Mezzofanti backend
  active at the same time.

  ## Using Mezzofanti

  To use `Mezzofanti`, you must defines a `Cldr` backend and a `Mezzofanti` backend.
  Refer to [ex_cldr's documentation]() for how to configure a `Cldr` locale.
  
      # Cldr backend to handle parsing and formatting ICU messages
      defmodule ExampleClrdBackend do
        use Cldr,
          default_locale: "en",
          locales: ["en", "pt-PT"],
          providers: [
            Cldr.Number,
            Cldr.DateTime,
            Cldr.Unit,
            Cldr.Calendar,
            Cldr.Message
          ]
      end

      # Mezzofanti backend that extracts translations
      # from `.po` and `.pot` files (used by gettext)
      defmodule ExampleMezzofantiBackend do
        use Mezzofanti.Backends.GettextBackend,
          otp_app: :mezzofanti,
          priv: "priv/mezzofanti"
      end

  Both backends should be configured in your app's `config.exs`:

      # config/config.exs
      config :mezzofanti,
        backend: ExampleMezzofantiBackend

      config :ex_cldr,
        default_locale: "en",
        default_backend: ExampleClrdBackend,
        json_library: Jason

  To translate strings in a module, you have to `use Mezzofanti` inside the module
  (it's *not* enough to `import Mezzofanti`, because the `use` macro adds some
  pre-compile hooks so that Mezzofanti is able to find the translated strings).
  This will import a `translate/2` macro into your module:

      defmodule ExampleModule do
        use Mezzofanti
        # Note that you don't need to require or import a Mezzofanti backend here.
        # Just use the Mezzofanti library, and once a backend is configured
        # it will automatically become aware of these messages
        # (even if the messages exist in a different application)

        def f() do
          # A simple static translation
          translate("Hello world!")
        end

        def g(guest) do
          # A translation with a variable.
          # This translation also contains a context (to disambiguate messages with the same text)
          translate("Hello {guest}!", context: "a message", variables: [guest: guest])
        end
      end

  The messages use the [ICU message format](https://unicode-org.github.io/icu/).
  This format is much more powerful and robust than Gettext.
  Support for ICU messages uses the
  [ex_cldr_messages](https://hexdocs.pm/ex_cldr_messages/readme.html),
  which is part of the [ex_cldr](https://hexdocs.pm/ex_cldr/readme.html)

  ## Translations

  Translations are stored inside PO (Portable Object) files, with a `.po`
  extension. For example, this is a snippet from a PO file:

      # This is a comment
      msgid "Hello world!"
      msgstr "Ciao mondo!"

  PO files containing translations for an application must be stored in a
  directory (by default it's `priv/gettext`) that has the following structure:

      gettext directory
      └─ locale
         └─ LC_MESSAGES
            ├─ domain_1.po
            ├─ domain_2.po
            └─ domain_3.po

  Here, `locale` is the locale of the translations (for example, `en_US`),
  `LC_MESSAGES` is a fixed directory, and `domain_i.po` are PO files containing
  domain-scoped translations.

  A concrete example of such a directory structure could look like this:

      priv/gettext
      └─ en_US
      |  └─ LC_MESSAGES
      |     ├─ default.po
      |     └─ errors.po
      └─ it
         └─ LC_MESSAGES
            ├─ default.po
            └─ errors.po

  By default, Mezzofanti expects translations to be stored under the `priv/mezzofanti`
  directory of an application. This behaviour can be changed by specifying a
  `:priv` option when using `Mezzofanti`:

      # Look for translations in my_app/priv/translations instead of
      # my_app/priv/mezzofanti

      use Gettext, otp_app: :my_app, priv: "priv/translations"

  The translations directory specified by the `:priv` option should be a directory
  inside `priv/`, otherwise some functions (like `mix extract.mezzofanti`) won't work
  as expected.

  ## Locale
  
  At runtime, all gettext-related functions and macros that do not explicitly
  take a locale as an argument read the locale from the process dictionary.

  `Cldr.put_locale/1` can be used to change the locale of all backends for
  the current Elixir process. That's the preferred mechanism for setting the
  locale at runtime.

  Similarly, `Cldr.get_locale/0` gets the locale for all backends in the
  current process. 
  
  `Gettext.get_locale/1` gets the locale of a specific backend
  for the current process. As mentioned above, the locale is stored **per-process**
  (in the process dictionary): this means that the locale must be set
  in every new process in order to have the right locale available for that process.
  Pay attention to this behaviour, since not setting the locale *will not*
  result in any errors when `Cldr.get_locale/0` or `Cldr.get_locale/1`
  are called; the default locale will be returned instead.
  """

  alias Mezzofanti.Message

  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :__mezzofanti_messages__, accumulate: true)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __mezzofanti_messages__(), do: @__mezzofanti_messages__
    end
  end

  @doc false
  # This is meant to be used mainly for testing.
  # The right place for this function is in Cldr and not Mezzofanti,
  # so we don't make it par of the "public API" for this module.
  def with_locale(locale, fun) do
    old_locale = Cldr.get_locale()

    try do
      Cldr.put_locale(locale)
      fun.()
    after
      Cldr.put_locale(old_locale)
    end
  end

  @doc """
  Translates a given string.

  It takes two arguments:

      * A *compile-time* string
      * An (optional) *compile-time* keyword list containing several `options`

  It accepts the following options:

      * `:variables` - variables to interpolate inside the string.
        Should be a keyword list of the form `[var1: value1, var2: value2]`
      * `:domain` - the domain of the translations. It must be a compile-time string.
        Domains will map to file names names inside the `priv/mezzofanti` directory.
        Of no domain is given, Mezzofanti assigns the message to the `"default"`
        domain.
      * `:context` - a context to disambiguate equal or similar messages

  A message is uniquely identified by the following three parameters:

      * The `string`
      * The `domain` (which if not given is assumed to "default")
      * The `context` (which may be the empty string)

  Mezzofanti is able to lookup all translations in all modules in your application
  (even dependencies), as long as you `use Mezzofanti`
  (instead of `import Mezzofanti).
  """
  defmacro translate(string, options \\ []) do
    line = __CALLER__.line
    file = __CALLER__.file
    module = __CALLER__.module
    domain = Keyword.get(options, :domain, "default")
    context = Keyword.get(options, :context, "")
    # TODO: Should we keep the `comment`?
    comment = Keyword.get(options, :comment, "")
    variables = Keyword.get(options, :variables, [])

    relative_path = Path.relative_to_cwd(file)

    message =
      Message.new(
        string: string,
        domain: domain,
        comment: comment,
        context: context,
        file: relative_path,
        line: line,
        module: module
      )

    Module.put_attribute(module, :__mezzofanti_messages__, message)

    quote do
      Mezzofanti.Translator.__translate__(
        unquote(message.hash),
        unquote(variables),
        unquote(Macro.escape(message))
      )
    end
  end
end
