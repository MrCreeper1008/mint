module Mint
  class Parser
    syntax_error IfExpectedTruthyOpeningBracket
    syntax_error IfExpectedTruthyClosingBracket
    syntax_error IfExpectedFalsyOpeningBracket
    syntax_error IfExpectedFalsyClosingBracket
    syntax_error IfExpectedOpeningParentheses
    syntax_error IfExpectedClosingParentheses
    syntax_error IfExpectedTruthyExpression
    syntax_error IfExpectedFalsyExpression
    syntax_error IfExpectedCondition
    syntax_error IfExpectedElse

    def if_expression
      if_expression { }
    end

    def css_if_expression
      if_expression(true) { css_definition }
    end

    def if_expression(multiple = false, &block : -> Ast::Node | Nil) : Ast::If | Nil
      start do |start_position|
        skip unless keyword "if"

        whitespace
        char '(', IfExpectedOpeningParentheses
        whitespace
        condition = expression! IfExpectedCondition
        whitespace
        char ')', IfExpectedClosingParentheses

        truthy_head_comments, truthy, truthy_tail_comments =
          block_with_comments(
            opening_bracket: IfExpectedTruthyOpeningBracket,
            closing_bracket: IfExpectedTruthyClosingBracket
          ) do
            if multiple
              many { block.call }.compact
            else
              expression! IfExpectedTruthyExpression
            end
          end

        whitespace
        keyword! "else", IfExpectedElse
        whitespace

        if falsy = if_expression
          falsy_head_comments = [] of Ast::Comment
          falsy_tail_comments = [] of Ast::Comment
        else
          falsy_head_comments, falsy, falsy_tail_comments =
            block_with_comments(
              opening_bracket: IfExpectedFalsyOpeningBracket,
              closing_bracket: IfExpectedFalsyClosingBracket
            ) do
              if multiple
                many { block.call }.compact
              else
                expression! IfExpectedFalsyExpression
              end
            end
        end

        Ast::If.new(
          truthy_head_comments: truthy_head_comments,
          truthy_tail_comments: truthy_tail_comments,
          falsy_head_comments: falsy_head_comments,
          falsy_tail_comments: falsy_tail_comments,
          condition: condition.as(Ast::Expression),
          branches: {truthy, falsy},
          from: start_position,
          to: position,
          input: data)
      end
    end
  end
end
