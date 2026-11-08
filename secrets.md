# 签名密钥

Android release 构建用的签名密钥放在项目根的 `secrets/` 目录, 该目录被 `.gitignore` 忽略.
docker 构建会自动读取这里的文件, 见 `docker/entrypoint.sh`.

## 文件

| 文件 | 说明 |
| --- | --- |
| `secrets/key.jks` | release 签名用的 keystore |
| `secrets/key.properties` | keystore 的密码与别名 |

## key.properties 格式

```properties
storeFile=key.jks
storePassword=<keystore 密码>
keyAlias=<别名>
keyPassword=<别名密码>
```

`storeFile` 写 `key.jks` 即可. 构建时 `key.properties` 会被放到 `android/`,
`key.jks` 会被放到 `android/app/`, gradle 以 app 模块为基准解析这个相对路径.

## 与 CI 的对应关系

CI 通过 GitHub Secrets 注入同样的内容:

| GitHub Secret | 对应的字段 |
| --- | --- |
| `SIGN_KEYSTORE_BASE64` | `key.jks` 的文件内容 (base64) |
| `KEYSTORE_PASSWORD` | `storePassword` |
| `KEY_ALIAS` | `keyAlias` |
| `KEY_PASSWORD` | `keyPassword` |

## 没有密钥时

删除或改名 `secrets/key.properties` 后, 构建会回退到 debug 签名, 产物只能本地安装, 不能用于分发.

## 注意

- keystore 一旦丢失, 已发布的包就无法再用新 keystore 覆盖安装, 请单独备份.
- 不要把密钥文件提交到仓库, 也不要把内容贴进 issue 或日志.
