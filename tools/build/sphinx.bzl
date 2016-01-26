def _apply_path_map(path_map, path):
    """ Apply the path mappings to a path.
        Replaces the longest prefix match from the mapping. """
    matchlen = 0
    match = path
    for x,y in path_map.items():
        if path.startswith(x):
            if len(x) > matchlen:
                match = y + path[len(x):]
                matchlen = len(x)
    return match

def _impl(ctx, builder):
    inputs = ctx.files.srcs
    output = ctx.outputs.out
    opts = ctx.attr.opts
    path_map = ctx.attr.path_map

    # TODO: make the following builder independent - don't want to install sphinx twice for html and latex
    sphinx_setup = ctx.new_file(ctx.configuration.genfiles_dir, 'sphinx-setup-%s' % builder)
    sphinx_env = ctx.new_file(ctx.configuration.genfiles_dir, 'sphinx-env-%s' % builder)
    sphinx_build = ctx.new_file(ctx.configuration.genfiles_dir, 'sphinx-build-%s' % builder)

    pylibs = [
        ctx.file._pbr,
        ctx.file._sphinx,
        ctx.file._sphinx_rtd_theme,
        ctx.file._alabaster,
        ctx.file._babel,
        ctx.file._docutils,
        ctx.file._jinja2,
        ctx.file._markupsafe,
        ctx.file._snowballstemmer,
        ctx.file._pygments,
        ctx.file._pytz,
        ctx.file._sphinxcontrib_spelling,
        ctx.file._pyenchant,
        ctx.file._six,
        ctx.file._sphinx_lua,
        ctx.file._sphinx_csharp
    ]

    subcommands = ['virtualenv env --quiet --no-site-packages']
    for lib in pylibs:
        subcommands.append('env/bin/python env/bin/pip install --quiet --no-deps %s' % lib.path)
    subcommands.append('tar -cf %s env' % sphinx_env.path)
    ctx.file_action(
        output = sphinx_setup,
        content = ' &&\n'.join(subcommands)+'\n',
        executable = True
    )

    ctx.action(
        inputs = pylibs,
        outputs = [sphinx_env],
        progress_message = 'Setting up sphinx',
        executable = sphinx_setup,
        use_default_shell_env = True
    )

    subcommands = [
        'tar -xf %s' % sphinx_env.path,
        'env/bin/python env/bin/sphinx-build -b %s -a -E -W -N -q "$1" "$2.files" $3' % builder # -j32
    ]
    if builder == 'html':
        subcommands.append('(CWD=`pwd` && cd "$2.files" && zip --quiet -r $CWD/$2 ./)')
    else:
        subcommands.append('make -C "$2.files" 1>/dev/null')
        subcommands.append('find "$2.files" -name *.pdf -exec cp {} $2 \;')
        subcommands.append('rm -rf "$2.files"')
    ctx.file_action(
        output = sphinx_build,
        content = ' &&\n'.join(subcommands)+'\n',
        executable = True
    )

    staging_dir = output.basename + '.sphinx-build-tmp'
    staging_dir_path = output.path.replace(
        ctx.configuration.bin_dir.path, ctx.configuration.genfiles_dir.path) + '.sphinx-build-tmp'
    staging_inputs = []
    for input in inputs:
        staging_path = staging_dir + '/' + _apply_path_map(path_map, input.short_path)
        staging_file = ctx.new_file(ctx.configuration.genfiles_dir, staging_path)

        ctx.action(
            mnemonic = 'StageDocFile',
            inputs = [input],
            outputs = [staging_file],
            command = 'ln -f -r -s %s %s' % (input.path, staging_file.path)
        )
        staging_inputs.append(staging_file)

    exec_reqs = {}
    if builder == 'latex':
        exec_reqs = {'local': ''} # pdflatex fails to run from the sandbox
    ctx.action(
        inputs = staging_inputs + [sphinx_env],
        outputs = [output],
        progress_message = 'Generating %s documentation' % builder,
        executable = sphinx_build,
        arguments = [staging_dir_path, output.path, ' '.join(['-D%s=%s' % x for x in opts.items()])],
        use_default_shell_env = True,
        execution_requirements = exec_reqs
    )

def _impl_html(ctx):
    _impl(ctx, 'html')

def _impl_latex(ctx):
    _impl(ctx, 'latex')

_SPHINX_ATTRS = {
    '_sphinx': attr.label(default=Label('@python.sphinx//file'),
                          allow_files=True, single_file=True),
    '_sphinx_rtd_theme': attr.label(default=Label('@python.sphinx_rtd_theme//file'),
                                    allow_files=True, single_file=True),
    '_alabaster': attr.label(default=Label('@python.alabaster//file'),
                             allow_files=True, single_file=True),
    '_babel': attr.label(default=Label('@python.babel//file'),
                         allow_files=True, single_file=True),
    '_docutils': attr.label(default=Label('@python.docutils//file'),
                            allow_files=True, single_file=True),
    '_jinja2': attr.label(default=Label('@python.jinja2//file'),
                          allow_files=True, single_file=True),
    '_markupsafe': attr.label(default=Label('@python.markupsafe//file'),
                              allow_files=True, single_file=True),
    '_snowballstemmer': attr.label(default=Label('@python.snowballstemmer//file'),
                                   allow_files=True, single_file=True),
    '_pygments': attr.label(default=Label('@python.pygments//file'),
                            allow_files=True, single_file=True),
    '_pytz': attr.label(default=Label('@python.pytz//file'),
                        allow_files=True, single_file=True),
    '_sphinxcontrib_spelling': attr.label(default=Label('@python.sphinxcontrib-spelling//file'),
                                          allow_files=True, single_file=True),
    '_pbr': attr.label(default=Label('@python.pbr//file'),
                       allow_files=True, single_file=True),
    '_pyenchant': attr.label(default=Label('@python.pyenchant//file'),
                             allow_files=True, single_file=True),
    '_six': attr.label(default=Label('@python.six//file'),
                       allow_files=True, single_file=True),
    '_sphinx_lua': attr.label(default=Label('@python.sphinx-lua//file'),
                              allow_files=True, single_file=True),
    '_sphinx_csharp': attr.label(default=Label('@python.sphinx-csharp//file'),
                                 allow_files=True, single_file=True)
}

sphinx_html = rule(
    implementation = _impl_html,
    attrs = {
        'srcs': attr.label_list(allow_files=True),
        'path_map': attr.string_dict(),
        'opts': attr.string_dict()
    } + _SPHINX_ATTRS,
    outputs = {'out': '%{name}.zip'}
)

sphinx_latex = rule(
    implementation = _impl_latex,
    attrs = {
        'srcs': attr.label_list(allow_files=True),
        'path_map': attr.string_dict(),
        'opts': attr.string_dict()
    } + _SPHINX_ATTRS,
    outputs = {'out': '%{name}.pdf'}
)