# git-gui Tools menu implementation

proc tools_list {} {
	global repo_config

	set names {}
	foreach item [array names repo_config guitool.*.cmd] {
		lappend names [string range $item 8 end-4]
	}
	return [lsort $names]
}

proc tools_populate_all {} {
	global tools_menubar tools_tailcnt tools_menus tools_menutbl

	array unset tools_menutbl

	set targets [list]
	if {[info exists tools_menubar]} {
		lappend targets [list $tools_menubar $tools_tailcnt]
	}
	if {[info exists tools_menus]} {
		foreach m $tools_menus {
			lappend targets [list $m 0]
		}
	}

	set tlist [tools_list]
	foreach item $targets {
		set target_menu [lindex $item 0]
		set tailcnt [lindex $item 1]
		if {![winfo exists $target_menu]} continue

		set m_end [$target_menu index end]
		if {$m_end ne {} && $m_end ne {none}} {
			set m_base [expr {$m_end - $tailcnt}]
			if {$m_base >= 0} {
				$target_menu delete 0 $m_base
			}
		}

		foreach fullname $tlist {
			tools_populate_one $target_menu $tailcnt $fullname
		}
	}
}

proc tools_create_item {parent target_menu tailcnt args} {
	if {$parent eq $target_menu} {
		set m_end [$parent index end]
		if {$m_end eq {} || $m_end eq {none}} {
			set pos 0
		} else {
			set pos [expr {$m_end - $tailcnt + 1}]
		}
		eval [list $parent insert $pos] $args
	} else {
		eval [list $parent add] $args
	}
}

proc tools_populate_one {target_menu tailcnt fullname} {
	global tools_menutbl tools_id

	if {![info exists tools_id]} {
		set tools_id 0
	}

	set names [split $fullname '/']
	set parent $target_menu
	for {set i 0} {$i < [llength $names]-1} {incr i} {
		set subname [join [lrange $names 0 $i] '/']
		if {[info exists tools_menutbl($target_menu,$subname)]} {
			set parent $tools_menutbl($target_menu,$subname)
		} else {
			set subid $parent.t$tools_id
			tools_create_item $parent $target_menu $tailcnt cascade \
					-label [lindex $names $i] -menu $subid
			menu $subid
			set tools_menutbl($target_menu,$subname) $subid
			set parent $subid
			incr tools_id
		}
	}

	tools_create_item $parent $target_menu $tailcnt command \
		-label [lindex $names end] \
		-command [list tools_exec $fullname]
}

proc tools_exec {fullname {line {}}} {
	global repo_config env current_diff_path
	global current_branch is_detached
	global selected_paths cursorX cursorY

	if {[is_config_true "guitool.$fullname.needsfile"]} {
		if {$current_diff_path eq {}} {
			error_popup [mc "Running %s requires a selected file." $fullname]
			return
		}
	}

	catch { unset env(ARGS) }
	catch { unset env(REVISION) }

	if {[get_config "guitool.$fullname.revprompt"] ne {} ||
	    [get_config "guitool.$fullname.argprompt"] ne {}} {
		set dlg [tools_askdlg::dialog $fullname]
		if {![tools_askdlg::execute $dlg]} {
			return
		}
	} elseif {[is_config_true "guitool.$fullname.confirm"]} {
		if {[is_config_true "guitool.$fullname.needsfile"]} {
			if {[ask_popup [mc "Are you sure you want to run %1\$s on file \"%2\$s\"?" $fullname $current_diff_path]] ne {yes}} {
				return
			}
		} else {
			if {[ask_popup [mc "Are you sure you want to run %s?" $fullname]] ne {yes}} {
				return
			}
		}
	}

	set env(GIT_GUITOOL) $fullname
	set env(FILENAME) $current_diff_path
	set env(FILENAMES) [join [array names selected_paths] \n]
	if {$is_detached} {
		set env(CUR_BRANCH) ""
	} else {
		set env(CUR_BRANCH) $current_branch
	}

	if {$line eq {}} {
		catch {
			set line [diff_find_line \
				[expr {[info exists cursorX] ? $cursorX : 0}] \
				[expr {[info exists cursorY] ? $cursorY : 0}]]
		}
	}
	if {$line ne {}} {
		set env(LINE) $line
	} else {
		catch { unset env(LINE) }
	}

	set cmdline $repo_config(guitool.$fullname.cmd)
	if {[is_config_true "guitool.$fullname.noconsole"]} {
		tools_run_silent [list [shellpath] -c $cmdline] \
				 [list tools_complete $fullname {}]
	} else {
		regsub {/} $fullname { / } title
		set w [console::new \
			[mc "Tool: %s" $title] \
			[mc "Running: %s" $cmdline]]
		console::exec $w [list [shellpath] -c $cmdline] \
				 [list tools_complete $fullname $w]
	}

	unset env(GIT_GUITOOL)
	unset env(FILENAME)
	unset env(FILENAMES)
	unset env(CUR_BRANCH)
	catch { unset env(ARGS) }
	catch { unset env(REVISION) }
	catch { unset env(LINE) }
}

proc tools_run_silent {cmd after} {
	set fd [safe_open_command $cmd [list 2>@1]]

	fconfigure $fd -blocking 0 -translation binary
	fileevent $fd readable [list tools_consume_input $fd $after]
}

proc tools_consume_input {fd after} {
	read $fd
	if {[eof $fd]} {
		fconfigure $fd -blocking 1
		if {[catch {close $fd}]} {
			uplevel #0 $after 0
		} else {
			uplevel #0 $after 1
		}
	}
}

proc tools_complete {fullname w {ok 1}} {
	if {$w ne {}} {
		console::done $w $ok
	}

	if {$ok} {
		set msg [mc "Tool completed successfully: %s" $fullname]
	} else {
		set msg [mc "Tool failed: %s" $fullname]
	}

	if {[is_config_true "guitool.$fullname.norescan"]} {
		ui_status $msg
	} else {
		rescan [list ui_status $msg]
	}
}
