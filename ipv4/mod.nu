def err [
  --span(-s): string
  --msg(-m): string
  --text(-t): string
] {
  error make {msg: $msg,label: {text: $text,start: $span.start,end: $span.end}}
}

export module from.nu
export module into.nu
export module cidr.nu