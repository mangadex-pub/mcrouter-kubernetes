# mcrouter for Kubernetes

## Summary

Facebook's [mcrouter](https://github.com/facebook/mcrouter) is a cool project for anyone with the need to horizontally
scale caching clusters in dynamic environments like Kubernetes, where specific workload instances cannot expect
unchanging internal IP addresses.

Finally, to achieve a truly dynamic setup is annoyingly verbose due to needing to regenerate JSON configuration files
and diff them on a timer after doing a bunch of DNS lookups per memcached cluster.

## Usage

Write your mcrouter configuration as you usually do, using `dnssrv:` prefix to get a dynamic list of servers in a pool
based on a headless Kubernetes service.

For example, for headless service `foo-headless` in namespace `memcache`:

```json
{
  "route": "PoolRoute|dynamic",
  "pools": {
    "dynamic": {
      "servers": [
        "dnssrv:_memcache._tcp.foo-headless.memcache.svc.cluster.local"
      ]
    }
  }
}
```

## Limitations

1. You can have pools with static servers, but you cannot mix dynamic and static server entries in the same pool
2. in-cluster IPv6 addressing is not supported
3. These images are downstream
   of [Wikipedia's images of mcrouter](https://docker-registry.wikimedia.org/mcrouter/tags/), as compiling mcrouter is
   currently exceedingly difficult, slow and resource-intensive (
   see [PR #449](https://github.com/facebook/mcrouter/pull/449) and linked issues/PRs). Debated instead using a plain
   image, but the extra size of a full image for 2 shell scripts seemed a little silly, when one probably wants to use a
   readymade mcrouter image anyway de to how annoying it is to build.
