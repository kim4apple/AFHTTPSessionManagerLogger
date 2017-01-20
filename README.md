# AFHTTPSessionManagerLogger

> Inspire by AFHTTPClientLogger.

**AFHTTPSessionManagerLogger** is a request logging extension for [AFNetworking][].  It

provides configurable HTTP request logging features on a per `AFHTTPSessionManager`
instance basis.

It is conceptually similar to [AFHTTPRequestOperationLogger][], which works
globally across all `AFHTTPSessionManager` instances.

AFHTTPSessionManagerLogger supports logging via [CocoaLumberjack][] and will use its logging methods over `NSLog` if it's available.

## Usage

The logger is accessed via the `logger` property of an `AFHTTPSessionManager` object
instance (simply named `manager` in the examples below).  It must be explicitly
enabled:

```objective-c
manager.logger.enabled = YES;
```

You can configure the log level to control the output's verbosity:

```objective-c
manager.logger.level = AFHTTPSessionManagerLogLevelDebug;
```

You can also customize the output by supplying your own format blocks:

```objective-c
[manager.logger setRequestStartFormatBlock:^NSString *(NSURLSessionTask *task, AFHTTPSessionManagerLogLevel level) {
    if (level > AFHTTPSessionManagerLogLevelInfo) {
        return nil;
    }

    return [NSString stringWithFormat:@"%@ %@", [task.originRequest HTTPMethod], [[task.originRequest URL] absoluteString]];
}];
```

## License

AFHTTPSessionManagerLogger is available under the MIT license.  See the included
LICENSE file for details.

## Contact

- Email: kim4apple@qq.com
- GitHub: [@kim4apple](https://github.com/kim4apple)


[AFNetworking]: http://afnetworking.com/
[CocoaLumberjack]: https://github.com/CocoaLumberjack/CocoaLumberjack
