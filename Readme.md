# Setup PHP SDK tool kit for Windows PHP builds

[![Test][test badge]][actions link]
[![MIT License][license badge]](./LICENSE)

[Github Action][ga-link] to set up an environment for building PHP extensions on Windows.

#### This action set up and configure:

- [PHP SDK][php-sdk-link] - a tool kit for Windows PHP builds
- [PHP Developer Pack][php-dev-pack-link] - libraries, c headers, scripts and phpize utility
- Add to system path SDK and Developer tools

## Usage

```yaml
- name: Setup PHP SDK with Developer Pack
  uses: zephir-lang/setup-php-sdk@v1.0
  with:
    php_version: '8.0'
    ts: 'nts'
    msvc: 'vs16'
    arch: 'x64'
    install_dir: 'C:\tools'
    cache_dir: 'C:\Downloads'
```

## Inputs

- `php_version`: the PHP version to build for (7.0, 7.1, 7.2, 7.3, 7.4, 8.0 or 8.1)
- `ts`: thread-safety (nts or ts). TS refers to multithread capable builds. NTS refers to single thread only builds. Default: `nts`
- `msvc`: the compiler toolset prefix, means Visual Studio version. (e.g: vc15 - Visual C++ 2017 compiler).
- `arch`: the target architecture to build for (x64 or x86). Default: `x64`
- `install_dir`: the target directory to install the sdk and devpack. (e.g: `C:\tools`)
- `cache_dir`: directory for downloaded files cache. If not specified - action will be using system tmp directory.


## License

Setup PHP SDK action licensed under the MIT License. See the [LICENSE](./LICENSE) file for more information.

<!-- All external links should be here -->
[ga-link]:              https://github.com/features/actions
[php-sdk-link]:         https://github.com/microsoft/php-sdk-binary-tools
[php-dev-pack-link]:    https://windows.php.net/

[test badge]:           https://github.com/zephir-lang/setup-php-sdk/actions/workflows/main.yml/badge.svg
[actions link]:         https://github.com/zephir-lang/setup-php-sdk/actions
[license badge]:        https://poser.pugx.org/phalcon/zephir/license.svg
