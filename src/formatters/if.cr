module Mint
  class Formatter
    def format(node : Ast::If) : String
      condition =
        format node.condition

      truthy_item, falsy_item =
        node.branches

      truthy =
        case truthy_item
        when Array(Ast::Node)
          list truthy_item + node.truthy_head_comments + node.truthy_tail_comments
        when Ast::Node
          list [truthy_item] + node.truthy_head_comments + node.truthy_tail_comments
        else
          ""
        end

      falsy =
        if falsy_item.is_a?(Ast::If) &&
           node.falsy_head_comments.empty? &&
           node.falsy_tail_comments.empty?
          format falsy_item
        else
          body =
            case falsy_item
            when Array(Ast::Node)
              list falsy_item + node.falsy_head_comments + node.falsy_tail_comments
            when Ast::Node
              list [falsy_item] + node.falsy_head_comments + node.falsy_tail_comments
            else
              ""
            end

          "{\n#{indent(body)}\n}"
        end

      condition =
        if replace_skipped(condition).includes?("\n")
          condition
            .remove_all_leading_whitespace
            .indent(4)
            .lstrip
        else
          condition
        end

      "if (#{condition}) {\n#{indent(truthy)}\n} else #{falsy}"
    end
  end
end
