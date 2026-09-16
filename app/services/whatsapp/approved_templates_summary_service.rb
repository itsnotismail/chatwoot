# Reduces a WhatsApp channel's synced templates to what a sender needs to choose one and fill its parameters:
# approved templates only, with variables per component. Namespaces, template ids, examples and provider config stay out.
class Whatsapp::ApprovedTemplatesSummaryService
  VARIABLE_PATTERN = /\{\{\s*([^{}]+?)\s*\}\}/

  pattr_initialize [:channel!]

  def perform
    (channel.message_templates || []).select { |template| template['status'].to_s.casecmp?('approved') }.map { |template| summarize(template) }
  end

  private

  def summarize(template)
    components = template['components'] || []
    {
      name: template['name'],
      language: template['language'],
      category: template['category'],
      status: template['status'],
      # TemplateProcessorService sends named body parameters only when this is exactly NAMED.
      parameter_format: template['parameter_format'] == 'NAMED' ? 'NAMED' : 'POSITIONAL',
      header: header_summary(find_component(components, 'HEADER')),
      body: body_summary(find_component(components, 'BODY')),
      buttons: buttons_summary(find_component(components, 'BUTTONS'))
    }
  end

  def find_component(components, type)
    components.find { |component| component['type'].to_s.casecmp?(type) }
  end

  def header_summary(header)
    return if header.blank?

    { format: (header['format'] || 'TEXT').upcase, variables: variables(header['text']) }
  end

  def body_summary(body)
    return if body.blank?

    { variables: variables(body['text']) }
  end

  def buttons_summary(buttons)
    return [] if buttons.blank?

    (buttons['buttons'] || []).each_with_index.map do |button, index|
      { index: index, type: button['type'].to_s.upcase, variables: variables(button['url']) }
    end
  end

  def variables(text)
    text.to_s.scan(VARIABLE_PATTERN).flatten.uniq
  end
end
