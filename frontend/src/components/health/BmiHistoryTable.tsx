import { useState } from "react";
import { ClipboardList, Trash2, AlertTriangle } from "lucide-react";
import type { BmiTimeSeriesRecord } from "@/types/health";

interface BmiHistoryTableProps {
  records: BmiTimeSeriesRecord[];
  loading?: boolean;
  onDelete: (id: number) => Promise<void> | void;
  deletingId?: number | null;
}

/** 达标状态徽章渲染 */
function GainStatusBadge({ status }: { status?: string | null }) {
  if (!status) {
    return <span className="text-xs text-gray-400">—</span>;
  }
  if (status === "normal") {
    return (
      <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-[11px] font-semibold text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300">
        增重达标
      </span>
    );
  }
  if (status === "below") {
    return (
      <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold text-amber-700 dark:bg-amber-950/50 dark:text-amber-300">
        增重偏低
      </span>
    );
  }
  return (
    <span className="rounded-full bg-red-100 px-2 py-0.5 text-[11px] font-semibold text-red-700 dark:bg-red-950/50 dark:text-red-300">
      增重超标
    </span>
  );
}

export default function BmiHistoryTable({ records, loading, onDelete, deletingId }: BmiHistoryTableProps) {
  const [confirmingId, setConfirmingId] = useState<number | null>(null);

  // 按时间倒序展示（最新打卡置顶），并标记最早一条为"基准"记录
  const sorted = [...records].sort((a, b) =>
    a.record_date === b.record_date ? b.id - a.id : a.record_date < b.record_date ? 1 : -1
  );
  const baselineId = sorted.length > 0 ? sorted[sorted.length - 1].id : null;

  const handleDeleteClick = (id: number) => {
    if (confirmingId === id) {
      onDelete(id);
      setConfirmingId(null);
    } else {
      setConfirmingId(id);
    }
  };

  return (
    <div className="card space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-orange-100/60 pb-3 dark:border-gray-800">
        <div className="flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-brand-50 text-brand-600 dark:bg-brand-950/60 dark:text-brand-400">
            <ClipboardList className="h-4 w-4" />
          </div>
          <div>
            <h3 className="text-base font-bold text-gray-800 dark:text-gray-100">
              测量打卡历史数据表
            </h3>
            <p className="text-xs text-gray-400">
              支持按天回溯历史打卡 · 删除后时序图表看板将自动联动刷新
            </p>
          </div>
        </div>
        <span className="rounded-full bg-orange-50 px-2.5 py-0.5 text-[11px] font-semibold text-brand-600 dark:bg-brand-950/50 dark:text-brand-300">
          共 {records.length} 条打卡
        </span>
      </div>

      {loading ? (
        <p className="py-10 text-center text-sm text-gray-400">历史数据加载中…</p>
      ) : sorted.length === 0 ? (
        <p className="py-10 text-center text-sm text-gray-400">
          暂无测量打卡记录，完成一次打卡后将在此形成可回溯的历史档案
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] text-left text-xs">
            <thead>
              <tr className="border-b border-gray-100 text-[11px] uppercase text-gray-400 dark:border-gray-800">
                <th className="px-3 py-2.5 font-semibold">测量日期</th>
                <th className="px-3 py-2.5 font-semibold">阶段</th>
                <th className="px-3 py-2.5 font-semibold">身高 (cm)</th>
                <th className="px-3 py-2.5 font-semibold">实测体重 (kg)</th>
                <th className="px-3 py-2.5 font-semibold">BMI</th>
                <th className="px-3 py-2.5 font-semibold">腹围 (cm)</th>
                <th className="px-3 py-2.5 font-semibold">增量 (Δ kg)</th>
                <th className="px-3 py-2.5 font-semibold">达标状态</th>
                <th className="px-3 py-2.5 text-right font-semibold">操作</th>
              </tr>
            </thead>
            <tbody>
              {sorted.map((r) => {
                const isBaseline = r.id === baselineId;
                const isConfirming = confirmingId === r.id;
                const isDeleting = deletingId === r.id;
                return (
                  <tr
                    key={r.id}
                    className="border-b border-gray-50 transition hover:bg-orange-50/40 dark:border-gray-800/60 dark:hover:bg-gray-800/40"
                  >
                    <td className="whitespace-nowrap px-3 py-2.5 font-medium text-gray-700 dark:text-gray-200">
                      {r.record_date}
                    </td>
                    <td className="whitespace-nowrap px-3 py-2.5 text-gray-600 dark:text-gray-400">
                      {r.stage === "postpartum"
                        ? r.postpartum_months != null
                          ? `产后 ${r.postpartum_months} 个月`
                          : "产后恢复"
                        : r.gestational_week
                        ? `孕 ${r.gestational_week} 周`
                        : r.stage === "pregnancy"
                        ? "孕期"
                        : r.record_type === "prenatal_exam"
                        ? r.gestational_week
                          ? `孕 ${r.gestational_week} 周`
                          : "孕期"
                        : "—"}
                    </td>
                    <td className="px-3 py-2.5 text-gray-600 dark:text-gray-400">
                      {r.height ?? "—"}
                    </td>
                    <td className="px-3 py-2.5 font-semibold text-gray-800 dark:text-gray-100">
                      {r.weight}
                    </td>
                    <td className="px-3 py-2.5 text-gray-600 dark:text-gray-400">
                      {r.bmi ?? "—"}
                    </td>
                    <td className="px-3 py-2.5 text-gray-600 dark:text-gray-400">
                      {r.waist_circumference ?? "—"}
                    </td>
                    <td className="px-3 py-2.5 text-gray-600 dark:text-gray-400">
                      {isBaseline ? (
                        <span className="text-gray-400">基准</span>
                      ) : (
                        <span
                          className={
                            r.delta_kg > 0.9
                              ? "font-semibold text-red-500"
                              : r.delta_kg > 0.6
                              ? "font-semibold text-amber-500"
                              : r.delta_kg < -0.5
                              ? "font-semibold text-indigo-500"
                              : "font-semibold text-emerald-600 dark:text-emerald-400"
                          }
                        >
                          {r.delta_kg > 0 ? "+" : ""}
                          {r.delta_kg}
                        </span>
                      )}
                    </td>
                    <td className="px-3 py-2.5">
                      <GainStatusBadge status={r.gain_status} />
                    </td>
                    <td className="px-3 py-2.5 text-right">
                      {isDeleting ? (
                        <span className="text-[11px] text-gray-400">删除中…</span>
                      ) : isConfirming ? (
                        <span className="inline-flex items-center gap-1.5">
                          <button
                            type="button"
                            onClick={() => handleDeleteClick(r.id)}
                            className="inline-flex items-center gap-1 rounded-lg bg-red-500 px-2 py-1 text-[11px] font-semibold text-white transition hover:bg-red-600"
                          >
                            <AlertTriangle className="h-3 w-3" />
                            确认删除
                          </button>
                          <button
                            type="button"
                            onClick={() => setConfirmingId(null)}
                            className="rounded-lg bg-gray-100 px-2 py-1 text-[11px] text-gray-500 transition hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-400 dark:hover:bg-gray-700"
                          >
                            取消
                          </button>
                        </span>
                      ) : (
                        <button
                          type="button"
                          onClick={() => handleDeleteClick(r.id)}
                          className="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-[11px] font-medium text-gray-400 transition hover:bg-red-50 hover:text-red-500 dark:hover:bg-red-950/40"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                          删除
                        </button>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
