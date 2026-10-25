class AssistantInputDecision {
  const AssistantInputDecision.use(this.text) : discard = false;
  const AssistantInputDecision.discard()
      : text = '',
        discard = true;
  final String text;
  final bool discard;
}
