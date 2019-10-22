module Mint
  # This is a name pool. It returns a unique identifier for a given item of a
  # given base item.
  #
  # In Mint it's used to get variable names for blocks of selectors
  # and CSS properties.
  class NamePool(T, B)
    INITIAL = 'a'.pred.to_s

    @cache : Hash(Tuple(B, T), String) = {} of Tuple(B, T) => String
    @current : Hash(B, String) = {} of B => String

    def of(subject : T, base : B)
      @cache[{base, subject}] ||= begin
        @current[base] = (@current[base]? || INITIAL).succ
      end
    end
  end

  # This class is responsible to build the CSS of "style" tags by resolving
  # nested media queries and selectors, handling cases of the same rules in
  # different places.
  class StyleBuilder
    alias Selector = Hash(String, String)

    getter selectors, property_pool, name_pool, style_pool, variables, ifs

    def initialize
      # Three name pools so there would be no clashes,
      # which also good for optimizations.
      @property_pool = NamePool(String, Selector).new
      @style_pool = NamePool(Ast::Node, Nil).new
      @name_pool = NamePool(Selector, Nil).new

      # This is the main data structure:
      #
      #   Hash(Tuple(MediaQueries, Selectors), Selector)
      #
      # Basically it allows to identify a specific set of rules in a
      # specific set of media queries in case their properties are
      # defined in serveral places.
      @selectors = {} of Tuple(Array(String), Array(String)) => Selector

      # This hash contains variables for a specific "style" tag, which will
      # be compiled by the compiler itself when compiling an HTML element
      # which uses the specific style tag.
      @variables = {} of Ast::Node => Hash(String, Array(String | Ast::CssInterpolation))
      @ifs = {} of Tuple(Ast::Node, Selector) => Array(Ast::If)
    end

    # Compiles the processed data into a CSS style sheet.
    def compile
      output = {} of Array(String) => Array(String)

      selectors
        .reject { |_, v| v.empty? }
        .each do |(medias, rules), properties|
          selector =
            rules.join(",\n")

          body =
            properties
              .map { |key, value| "#{key}: #{value};" }
              .join("\n")

          output[medias] ||= [] of String
          output[medias] << "#{selector} {\n#{body.indent}\n}"
        end

      output.map do |medias, rules|
        if medias.any?
          "@media #{medias.join(" and ")} {\n#{rules.join("\n\n").indent}\n}"
        else
          rules.join("\n\n")
        end
      end.join("\n\n")
    end

    def compile_style(node : Ast::Style, compiler : Compiler)
      ifs.select(&.first.==(node))
        .map do |(_, selector), selector_ifs|
          selector_ifs.map do |item|
            condition =
              compiler.compile item.condition

            thruty, falsy =
              item.branches

            thruty_items =
              case thruty
              when Array(Ast::Node)
                items =
                  thruty
                    .select(&.is_a?(Ast::CssDefinition))
                    .each_with_object({} of String => String) do |definition, memo|
                      a =
                        definition.as(Ast::CssDefinition)

                      variable =
                        variable_name a.name, selector

                      selector[a.name] =
                        "var(#{variable})"

                      value =
                        compiler.compile a.value

                      memo["[`#{variable}`]"] = "`#{value}`"
                    end

                compiler.js.object(items)
              end

            falsy_items =
              case falsy
              when Array(Ast::Node)
                items =
                  falsy
                    .select(&.is_a?(Ast::CssDefinition))
                    .each_with_object({} of String => String) do |definition, memo|
                      a =
                        definition.as(Ast::CssDefinition)

                      variable =
                        variable_name a.name, selector

                      selector[a.name] =
                        "var(#{variable})"

                      value =
                        compiler.compile a.value

                      memo["[`#{variable}`]"] = "`#{value}`"
                    end

                compiler.js.object(items)
              end

            compiler.js.get("_" + style_pool.of(node, nil),
              compiler.js.statements([
                compiler.js.const("_", "{}"),
                compiler.js.if(condition, "Object.assign(_, #{thruty_items})") + " " +
                compiler.js.else { "Object.assign(_, #{falsy_items})" },
                compiler.js.return("_"),
              ]))
          end.join("\n\n")
        end.join("\n\n")
    end

    # The main entry point for processing a "style" tag.
    def process(node : Ast::Style)
      selectors =
        ["." + style_pool.of(node, nil)]

      process(node.body, selectors, [] of String, node)
    end

    # Processes an Ast::CssSelector
    def process(node : Ast::CssSelector,
                parents : Array(String),
                media : Array(String),
                style_node : Ast::Node)
      selectors = [] of String

      parents.each do |parent|
        node.selectors.map do |item|
          selectors << parent + item
        end
      end

      process(node.body, selectors, media, style_node)
    end

    # Processes an Ast::Media
    def process(node : Ast::CssMedia,
                selectors : Array(String),
                media : Array(String),
                style_node : Ast::Node)
      process(node.body, selectors, media + [node.content], style_node)
    end

    # Processes the body of a CSS Ast::Node.
    def process(body : Array(Ast::Node),
                selectors : Array(String),
                media : Array(String),
                style_node : Ast::Node)
      # Create a selector for this specific state
      selector =
        @selectors[{media, selectors}] ||= Selector.new

      body.each do |item|
        case item
        when Ast::CssDefinition
          if item.value.any?(Ast::CssInterpolation)
            # Get the name of the variable
            variable =
              variable_name(item.name, selector)

            selector[item.name] = "var(#{variable})"

            # Save the actual data for the variable for compiling later.
            variables[style_node] ||= {} of String => Array(String | Ast::CssInterpolation)
            variables[style_node][variable] = item.value
          else
            selector[item.name] = item.value.join("")
          end
        when Ast::CssSelector
          process(item, selectors, media, style_node)
        when Ast::CssMedia
          process(item, selectors, media, style_node)
        when Ast::If
          ifs[{style_node, selector}] ||= [] of Ast::If
          ifs[{style_node, selector}] << item
        end
      end
    end

    private def variable_name(name, selector)
      # Get the unique ID of the selector
      block_id =
        name_pool.of(selector, nil)

      # Get the unique ID of the property
      variable_id =
        property_pool.of(name, selector)

      "--#{block_id}-#{variable_id}"
    end
  end
end
