# Reduces a WhatsApp channel's synced templates to what a sender needs to choose one and fill its parameters:
# approved templates only, with variables and parameter hints per component. Template ids, examples and provider config
# stay out. The namespace is included for 360dialog channels only, because that provider sends it with every template.
class Whatsapp::ApprovedTemplatesSummaryService
  VARIABLE_PATTERN = /\{\{\s*([^{}]+?)\s*\}\}/
  PARAMETER_HEADER_FORMATS = %w[IMAGE VIDEO DOCUMENT LOCATION].freeze
  PARAMETER_BUTTON_TYPES = %w[OTP COPY_CODE FLOW].freeze

  pattr_initialize [:channel!]

  def perform
    (channel.message_templates || []).select { |template| template['status'].to_s.casecmp?('approved') }.map { |template| summarize(template) }
  end

  private

  def summarize(template)
    components = template['components'] || []
    # TemplateProcessorService sends named body parameters only when this is exactly NAMED.
    named = template['parameter_format'] == 'NAMED'
    summary = {
      name: template['name'], language: template['language'], category: template['category'], status: template['status'],
      parameter_format: named ? 'NAMED' : 'POSITIONAL',
      header: header_summary(find_component(components, 'HEADER'), named),
      body: body_summary(find_component(components, 'BODY')),
      buttons: buttons_summary(find_component(components, 'BUTTONS'))
    }
    summary[:namespace] = template['namespace'] if channel.provider == 'default'
    summary
  end

  def find_component(components, type)
    components.find { |component| component['type'].to_s.casecmp?(type) }
  end

  def header_summary(header, named)
    return if header.blank?

    format = (header['format'] || 'TEXT').upcase
    header_variables = variables(header['text'])
    {
      format: format,
      variables: header_variables,
      requires_parameter: header_variables.any? || PARAMETER_HEADER_FORMATS.include?(format),
      # The send path fills header text values by position, without parameter_name, even for NAMED templates.
      named_variables_filled_by_position: named && header_variables.any?
    }
  end

  def body_summary(body)
    return if body.blank?

    body_variables = variables(body['text'])
    { variables: body_variables, requires_parameter: body_variables.any? }
  end

  def buttons_summary(buttons)
    return [] if buttons.blank?

    (buttons['buttons'] || []).each_with_index.map do |button, index|
      type = button['type'].to_s.upcase
      button_variables = variables(button['url'])
      { index: index, type: type, variables: button_variables,
        requires_parameter: button_variables.any? || PARAMETER_BUTTON_TYPES.include?(type) }
    end
  end

  def variables(text)
    text.to_s.scan(VARIABLE_PATTERN).flatten.uniq
  end
end
