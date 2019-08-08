To generate the documentation

```
$ jazzy
```



To update the [web](https://4th-atechnologies.github.io/ZeroDark.cloud/)

```
$ rsync -a --itemize-changes docs/ ../apis.zerodark.cloud/
```

*Note: The trailing slashes are important.*

