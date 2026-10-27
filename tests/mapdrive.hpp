// mapdrive.hpp - runs a gsa1::MapJob to the end on the calling thread, the way the addon drives it frame by frame:
// MapPoll, the byte ranges it needs read from the map file in pieces (fed mode: what Lua's file.Open / Seek / Read
// does for workshop maps), the model files it asks for from a GameFs (gamefs.hpp). For the tests and tools.
#pragma once

#include <string>
#include <utility>
#include <vector>

#include "gamefs.hpp"
#include "mapjob.hpp"

struct MapDrive {
    int polls = 0;
    uint64_t fed = 0;
    uint32_t files = 0, files_found = 0;
};

// fed_path: the map file the "addon" reads in fed mode (nullptr: the job reads its file itself); fed_base: where the
// map starts in that file (a map inside a workshop GMA)
inline bool run_map_job(gsa1::MapJob &job, gamefs::GameFs *fs, const std::string *fed_path, std::string &err,
                        MapDrive *d = nullptr, uint64_t piece = 1u << 20, uint64_t fed_base = 0)
{
    MapDrive local;
    MapDrive &D = d ? *d : local;
    for (;;) {
        job.wait();
        job.poll();
        D.polls++;
        gsa1::MapState s = job.state();
        if (s == gsa1::MapState::Ready) {
            return true;
        }
        if (s == gsa1::MapState::Failed) {
            err = job.error();
            return false;
        }
        if (s == gsa1::MapState::Reading) {
            if (!fed_path) {
                err = "the job wants map bytes in file mode";
                return false;
            }
            std::vector<std::pair<uint64_t, uint64_t>> needs;
            job.needs(needs, 32, piece);
            for (const auto &r : needs) {
                std::string b;
                if (!gamefs::read_range(*fed_path, fed_base + r.first, (size_t)r.second, b) ||
                    !job.feed(r.first, b.data(), b.size(), err)) {
                    err = "feeding the map: " + err;
                    return false;
                }
                D.fed += b.size();
            }
        } else if (s == gsa1::MapState::Files) {
            std::vector<std::pair<std::string, uint32_t>> files;
            job.files(files, 64);
            for (const auto &f : files) {
                std::string b;
                D.files++;
                bool ok = fs && fs->read(f.first, b, f.second);
                D.files_found += ok;
                if (!job.feed_file(f.first, ok ? b.data() : nullptr, ok ? b.size() : 0, err)) {
                    return false;
                }
            }
        }
        if (D.polls > 1000000) {
            err = "the job does not finish";
            return false;
        }
    }
}
