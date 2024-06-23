use std log

export def handle_exit_code [
    --msg(-m):string
] {
    let co: record<stdout:string,stderr:string,exit_code:int> = $in
    match $co {
        {stdout: _, stderr: _, exit_code: 0} => { true }
        _ => {
            print $'Exit Code: ($co.exit_code)(char newline)($msg)(char newline)($co.stderr)'
            false
        }
    }
}


export def sub [
    --command(-c):string
    --sub_commands(-s):list<string>
] {
    for scmd in $sub_commands {
        let cmd_info = ($command | append $scmd | str join (char space))
        print $'# starting: ($cmd_info)'

        run-external $command $scmd
        | tee {print}
        | complete
        | handle_exit_code -m $'($cmd_info) failed!'
        | do {|success:bool| if $success {()} else {break} } $in
    }
}
