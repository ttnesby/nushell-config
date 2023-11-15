# module err - throw custom error
export def main [
  --span(-s): record<start: int, end: int>
  --msg(-m): string
  --text(-t): string
] {
  error make {
    msg: $msg, 
    label: {
      text: $text, 
      start: $span.start, 
      end: $span.end
    }
  }
}